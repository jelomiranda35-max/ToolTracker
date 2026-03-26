import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/db_helper.dart';
import '../models/instrument.dart';
import 'api_service.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;

  static Future<bool> isConnected() async {
    try {
      final result = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
return !result.contains(ConnectivityResult.none) && result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void startListening() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        syncAll();
      }
    });
  }

  void stopListening() {
    _connectivitySubscription?.cancel();
  }

  /// Full sync with a hard 30-second timeout so it never hangs forever.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) return SyncResult(synced: 0, failed: 0, pulled: 0);
    if (!await isConnected()) return SyncResult(synced: 0, failed: 0, pulled: 0);

    _isSyncing = true;

    try {
      return await _doSync().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _isSyncing = false;
          return SyncResult(synced: 0, failed: 0, pulled: 0);
        },
      );
    } catch (e) {
      return SyncResult(synced: 0, failed: 0, pulled: 0);
    } finally {
      _isSyncing = false;
    }
  }

  Future<SyncResult> _doSync() async {
    int synced = 0;
    int failed = 0;
    int pulled = 0;
    // ── STEP 0: Push locally-edited instruments to server ─────────────────
    // Catches edits made while offline that the inline push in
    // updateInstrumentDetails() silently skipped.
    try {
      final edited = await DBHelper.instance.getLocallyEditedInstruments()
          .timeout(const Duration(seconds: 5));
      for (final inst in edited) {
        try {
          final patchBody = <String, dynamic>{
            'current_condition': inst.currentCondition,
            'location': inst.location ?? '',
            'scheduled_repair_date': inst.scheduledRepairDate ?? '',
            'scheduled_condemn_date': inst.scheduledCondemnDate ?? '',
            'notes': inst.notes ?? '',
            if (inst.lastCalibratedDate != null)
              'last_calibrated_date': inst.lastCalibratedDate!,
            if (inst.calibrationNotes != null)
              'calibration_notes': inst.calibrationNotes!,
          };
          final success = await ApiService.patchInstrument(
            inst.instrumentCode,
            patchBody,
          ).timeout(const Duration(seconds: 8));
          if (success) {
            final db = await DBHelper.instance.database;
            await db.update(
              'instruments',
              {
                'condition_edited_locally': 0,
                'schedule_edited_locally': 0,
              },
              where: 'instrument_code = ?',
              whereArgs: [inst.instrumentCode],
            );
            synced++;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {}
    // ── STEP 1: Pull instruments from server ──────────────────────────────
    // IMPORTANT: Use upsertInstrumentFromServer (NOT insertInstrument) so that:
    //   - scheduled_repair_date, scheduled_condemn_date, notes are preserved
    //   - locally-edited current_condition is NOT overwritten by a stale server value
    try {
      final instruments = await ApiService.getInstruments()
          .timeout(const Duration(seconds: 10));
      if (instruments != null) {
        for (final i in instruments) {
          try {
            final instrument = Instrument.fromMap({
              'instrument_code': i['instrument_code'] ?? '',
              'instrument_name': i['instrument_name'] ?? '',
              'serial_number': i['serial_number'],
              'current_condition': i['current_condition'] ?? 'Functioning',
              'status': i['status'] ?? 'Available',
              'location': i['location'] ?? 'AMTEC UPLB',
              'last_touch_date': i['last_touch_date']?.toString(),
              'last_touch_by': i['last_touch_by'],
              'last_updated': i['last_updated']?.toString(),
              // Pass server's schedule values so other devices receive edits
              // made on different devices. upsertInstrumentFromServer will only
              // apply them when schedule_edited_locally == 0 on this device.
              'scheduled_repair_date': i['scheduled_repair_date'],
              'scheduled_condemn_date': i['scheduled_condemn_date'],
              'notes': i['notes'],
              'last_calibrated_date': i['last_calibrated_date'],
              'calibration_notes': i['calibration_notes'],
            });
            // ✅ FIX: was insertInstrument() which used ConflictAlgorithm.replace
            // and wiped current_condition. Now uses upsertInstrumentFromServer()
            // which protects locally-edited fields.
            await DBHelper.instance.upsertInstrumentFromServer(instrument);
          } catch (_) {}
        }
      }
    } catch (_) {}

    // ── STEP 2: Pull ALL dispatches from server ───────────────────────────
    try {
      final serverDispatches = await ApiService.getDispatches()
          .timeout(const Duration(seconds: 10));
      if (serverDispatches != null) {
        for (final d in serverDispatches) {
          try {
            await DBHelper.instance.upsertDispatchFromServer(
                Map<String, dynamic>.from(d));
            pulled++;
          } catch (_) {}
        }
      }
    } catch (_) {}

    // ── STEP 3: Push local pending dispatches to server ───────────────────
    try {
      final pending = await DBHelper.instance.getPendingSync();

      for (final dispatch in pending) {
        if (dispatch.id == null) continue;

        try {
          final items =
              await DBHelper.instance.getDispatchItems(dispatch.id!);

          if (dispatch.dateIn != null) {
            // Completed return — push return endpoint WITH item conditions
            final itemConditions = items
                .where((i) => i.returnCondition != null)
                .map((i) => {
                      'instrument_code': i.instrumentCode,
                      'return_condition': i.returnCondition!,
                    })
                .toList();

            final success = await ApiService.returnDispatchWithConditions(
              dispatch.dispatchNo,
              itemConditions: itemConditions,
            ).timeout(const Duration(seconds: 8));

            if (success) {
              await DBHelper.instance.markSynced(dispatch.id!);
              synced++;
            } else {
              failed++;
            }
          } else {
            // New dispatch — push create endpoint
            final success = await ApiService.createDispatch({
              'dispatch_no': dispatch.dispatchNo,
              'test_engineer': dispatch.testEngineer,
              'processed_by_id': dispatch.processedById,
              'date_out': dispatch.dateOut,
              'remarks': dispatch.remarks,
              'dispatch_type': dispatch.dispatchType,
              'student_name': dispatch.studentName,
              'student_id': dispatch.studentId,
              'items': items
                  .map((i) => {
                        'instrument_code': i.instrumentCode,
                        'current_condition': i.currentCondition,
                        'remarks': i.remarks,
                      })
                  .toList(),
            }).timeout(const Duration(seconds: 8));

            if (success) {
              await DBHelper.instance.markSynced(dispatch.id!);
              synced++;
            } else {
              failed++;
            }
          }
        } catch (_) {
          failed++;
        }
      }
    } catch (_) {}

    // ── STEP 4: Push local activity logs to server ────────────────────────
    try {
      final db = await DBHelper.instance.database;
      final unsynced = await db.query('activity_log',
          where: 'synced_to_server = 0 OR synced_to_server IS NULL',
          orderBy: 'timestamp ASC',
          limit: 200);
      if (unsynced.isNotEmpty) {
        final entries = unsynced.map((r) => {
          'event_type': r['event_type'],
          'event_detail': r['event_detail'],
          'actor': r['actor'],
          'device_info': r['device_info'],
          'timestamp': r['timestamp'],
        }).toList();
        final ok = await ApiService.postActivityLog(entries);
        if (ok) {
          final ids = unsynced.map((r) => r['id'] as int).toList();
          for (final id in ids) {
            await db.update('activity_log',
                {'synced_to_server': 1},
                where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    } catch (_) {}

    // ── STEP 5: Push local instrument history to server ───────────────────
    try {
      final db = await DBHelper.instance.database;
      final unsynced = await db.query('instrument_history',
          where: 'synced_to_server = 0 OR synced_to_server IS NULL',
          orderBy: 'timestamp ASC',
          limit: 200);
      if (unsynced.isNotEmpty) {
        final entries = unsynced.map((r) => {
          'instrument_code': r['instrument_code'],
          'event_type': r['event_type'],
          'event_detail': r['event_detail'],
          'actor': r['actor'],
          'timestamp': r['timestamp'],
        }).toList();
        final ok = await ApiService.postInstrumentHistory(entries);
        if (ok) {
          final ids = unsynced.map((r) => r['id'] as int).toList();
          for (final id in ids) {
            await db.update('instrument_history',
                {'synced_to_server': 1},
                where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    } catch (_) {}

    // ── STEP 6: Push pending revert requests to server ────────────────────
    try {
      final db6 = await DBHelper.instance.database;
      final pending = await db6.query('revert_requests',
          where: 'status = ?', whereArgs: ['pending'],
          orderBy: 'requested_at ASC');
      if (pending.isNotEmpty) {
        final entries = pending.map((r) => {
          'instrument_code': r['instrument_code'],
          'instrument_name': r['instrument_name'],
          'requested_condition': r['requested_condition'],
          'reason': r['reason'],
          'requested_by': r['requested_by'],
          'requested_at': r['requested_at'],
        }).toList();
        await ApiService.postRevertRequests(entries);
      }
    } catch (_) {}

    // ── STEP 7: Pull revert request decisions from server ─────────────────
    try {
      final decisions = await ApiService.getRevertRequests();
      if (decisions != null) {
        for (final d in decisions) {
          try {
            final code = d['instrument_code'] as String? ?? '';
            final status = d['status'] as String? ?? '';
            if (code.isEmpty || status == 'pending') continue;
            // Check local status
            final db7 = await DBHelper.instance.database;
            final local = await db7.query('revert_requests',
                where: 'instrument_code = ? AND status = ?',
                whereArgs: [code, 'pending']);
            if (local.isNotEmpty) {
              if (status == 'approved') {
                final requestedCondition =
                    d['requested_condition'] as String? ?? 'Functioning';
                await DBHelper.instance.approveRevertRequest(
                    code, requestedCondition);
              } else if (status == 'denied') {
                await DBHelper.instance.denyRevertRequest(code);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Mark first sync as done so new instrument alerts fire correctly going forward
    await DBHelper.instance.setFirstSyncDone();

    return SyncResult(synced: synced, failed: failed, pulled: pulled);
  }

  /// Kept for backwards compatibility
  Future<SyncResult> syncPending() => syncAll();

  Future<int> getPendingCount() async {
    final pending = await DBHelper.instance.getPendingSync();
    return pending.length;
  }
}

class SyncResult {
  final int synced;
  final int failed;
  final int pulled;
  SyncResult(
      {required this.synced, required this.failed, required this.pulled});
}