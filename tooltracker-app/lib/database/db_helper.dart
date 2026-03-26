import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import '../models/instrument.dart';
import '../models/dispatch.dart';
import '../services/api_service.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tooltracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 14,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // ── Schema creation (fresh install) ─────────────────────────────────────────

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE instruments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        instrument_code TEXT UNIQUE NOT NULL,
        instrument_name TEXT NOT NULL,
        serial_number TEXT,
        current_condition TEXT NOT NULL DEFAULT 'Functioning',
        status TEXT NOT NULL DEFAULT 'Available',
        location TEXT DEFAULT 'AMTEC UPLB',
        last_touch_date TEXT,
        last_touch_by TEXT,
        last_updated TEXT,
        scheduled_repair_date TEXT,
        scheduled_condemn_date TEXT,
        notes TEXT,
        condition_edited_locally INTEGER DEFAULT 0,
        schedule_edited_locally INTEGER DEFAULT 0,
        last_calibrated_date TEXT,
        calibration_notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE dispatches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dispatch_no TEXT UNIQUE NOT NULL,
        test_engineer TEXT NOT NULL,
        processed_by_id INTEGER NOT NULL,
        processed_by_name TEXT,
        date_out TEXT NOT NULL,
        date_in TEXT,
        remarks TEXT,
        return_photo_paths TEXT,
        synced INTEGER DEFAULT 0,
        conflict INTEGER DEFAULT 0,
        dispatch_type TEXT DEFAULT 'staff',
        student_name TEXT,
        student_id TEXT,
        student_form_photo_path TEXT,
        borrower_contact TEXT,
        borrower_email TEXT,
        borrower_purpose TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE dispatch_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dispatch_id INTEGER NOT NULL,
        instrument_code TEXT NOT NULL,
        instrument_name TEXT NOT NULL,
        current_condition TEXT NOT NULL,
        return_condition TEXT,
        remarks TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE instrument_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        instrument_code TEXT NOT NULL,
        event_type TEXT NOT NULL,
        event_detail TEXT,
        actor TEXT,
        timestamp TEXT NOT NULL,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

        await db.execute('''
      CREATE TABLE condemn_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        instrument_code TEXT NOT NULL,
        instrument_name TEXT,
        scheduled_condemn_date TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        requested_at TEXT NOT NULL,
        responded_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE revert_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        instrument_code TEXT NOT NULL,
        instrument_name TEXT,
        requested_condition TEXT NOT NULL,
        reason TEXT NOT NULL,
        requested_by TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        requested_at TEXT NOT NULL,
        responded_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE activity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        event_detail TEXT,
        actor TEXT,
        device_info TEXT,
        timestamp TEXT NOT NULL,
        synced_to_server INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE admin_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        from_admin_id INTEGER,
        from_admin_name TEXT,
        to_user_id INTEGER,
        to_user_name TEXT,
        message TEXT NOT NULL,
        created_at TEXT NOT NULL,
        read_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE new_instrument_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        instrument_code TEXT NOT NULL,
        instrument_name TEXT NOT NULL,
        serial_number TEXT,
        added_at TEXT NOT NULL,
        shown INTEGER DEFAULT 0
      )
    ''');
  }

  // ── Incremental migrations ───────────────────────────────────────────────────

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE dispatches ADD COLUMN processed_by_name TEXT');
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
            'ALTER TABLE dispatch_items ADD COLUMN return_condition TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE dispatches ADD COLUMN return_photo_paths TEXT');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN scheduled_repair_date TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN scheduled_condemn_date TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE instruments ADD COLUMN notes TEXT');
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE dispatches ADD COLUMN dispatch_type TEXT DEFAULT 'staff'");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE dispatches ADD COLUMN student_name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE dispatches ADD COLUMN student_id TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE dispatches ADD COLUMN student_form_photo_path TEXT');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      // Track whether condition was edited locally so sync doesn't overwrite it
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN condition_edited_locally INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      // Track whether schedule/notes were edited locally so sync won't overwrite
      // them with server data from a DIFFERENT device's edits.
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN schedule_edited_locally INTEGER DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      // New borrower fields on dispatches
      try {
        await db.execute('ALTER TABLE dispatches ADD COLUMN borrower_contact TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE dispatches ADD COLUMN borrower_email TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE dispatches ADD COLUMN borrower_purpose TEXT');
      } catch (_) {}
      // Instrument history log table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS instrument_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_detail TEXT,
            actor TEXT,
            timestamp TEXT NOT NULL,
            synced_to_server INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE activity_log ADD COLUMN IF NOT EXISTS synced_to_server INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE instrument_history ADD COLUMN IF NOT EXISTS synced_to_server INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS condemn_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT,
            scheduled_condemn_date TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            requested_at TEXT NOT NULL,
            responded_at TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS activity_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            event_detail TEXT,
            actor TEXT,
            device_info TEXT,
            timestamp TEXT NOT NULL,
            synced_to_server INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS revert_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT,
            requested_condition TEXT NOT NULL,
            reason TEXT NOT NULL,
            requested_by TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            requested_at TEXT NOT NULL,
            responded_at TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS admin_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            from_admin_id INTEGER,
            from_admin_name TEXT,
            to_user_id INTEGER,
            to_user_name TEXT,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            read_at TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS new_instrument_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT NOT NULL,
            serial_number TEXT,
            added_at TEXT NOT NULL,
            shown INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    // ── Version 12: Safety net — guarantee revert_requests exists ────────────
    if (oldVersion < 12) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS revert_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT,
            requested_condition TEXT NOT NULL,
            reason TEXT NOT NULL,
            requested_by TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            requested_at TEXT NOT NULL,
            responded_at TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS condemn_requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT,
            scheduled_condemn_date TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            requested_at TEXT NOT NULL,
            responded_at TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS activity_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            event_detail TEXT,
            actor TEXT,
            device_info TEXT,
            timestamp TEXT NOT NULL,
            synced_to_server INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS admin_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            from_admin_id INTEGER,
            from_admin_name TEXT,
            to_user_id INTEGER,
            to_user_name TEXT,
            message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            read_at TEXT
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS new_instrument_alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            instrument_code TEXT NOT NULL,
            instrument_name TEXT NOT NULL,
            serial_number TEXT,
            added_at TEXT NOT NULL,
            shown INTEGER DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    // ── Version 13: Add calibration fields ───────────────────────────────────
    if (oldVersion < 13) {
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN last_calibrated_date TEXT');
      } catch (_) {}
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN calibration_notes TEXT');
      } catch (_) {}
      // Set last_calibrated_date = last_updated for all existing instruments
      // so they don't immediately trigger calibration overdue alerts
      try {
        await db.execute('''
          UPDATE instruments
          SET last_calibrated_date = COALESCE(last_updated, datetime('now'))
          WHERE last_calibrated_date IS NULL
        ''');
      } catch (_) {}
    }
    // ── Version 14: Add next_calibration_due field ────────────────────────
    if (oldVersion < 14) {
      try {
        await db.execute(
            'ALTER TABLE instruments ADD COLUMN next_calibration_due TEXT');
      } catch (_) {}
    }
  }

  // ── REVERT REQUESTS ───────────────────────────────────────────────────────

  Future<void> insertRevertRequest({
    required String instrumentCode,
    required String instrumentName,
    required String requestedCondition,
    required String reason,
    String? requestedBy,
  }) async {
    final db = await database;
    await db.insert('revert_requests', {
      'instrument_code': instrumentCode,
      'instrument_name': instrumentName,
      'requested_condition': requestedCondition,
      'reason': reason,
      'requested_by': requestedBy,
      'status': 'pending',
      'requested_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingRevertRequests() async {
    final db = await database;
    return await db.query('revert_requests',
        where: 'status = ?', whereArgs: ['pending'], orderBy: 'requested_at DESC');
  }

  Future<void> approveRevertRequest(String instrumentCode, String newCondition) async {
    final db = await database;
    await db.update('revert_requests',
        {'status': 'approved', 'responded_at': DateTime.now().toIso8601String()},
        where: 'instrument_code = ? AND status = ?',
        whereArgs: [instrumentCode, 'pending']);
    await updateInstrumentDetails(
      code: instrumentCode,
      condition: newCondition,
    );
    // Clear locally-edited flag so sync pushes the new condition to server
    // instead of accidentally re-pushing the old Condemning condition
    await db.update(
      'instruments',
      {'condition_edited_locally': 1},
      where: 'instrument_code = ?',
      whereArgs: [instrumentCode],
    );
  }

  Future<void> denyRevertRequest(String instrumentCode) async {
    final db = await database;
    await db.update('revert_requests',
        {'status': 'denied', 'responded_at': DateTime.now().toIso8601String()},
        where: 'instrument_code = ? AND status = ?',
        whereArgs: [instrumentCode, 'pending']);
  }

  // ── INSTRUMENT HISTORY ────────────────────────────────────────────────────

  /// Log an event for a specific instrument.
  /// event_type values: 'added', 'dispatched', 'borrowed', 'returned',
  ///   'condition_changed', 'location_changed'
  Future<void> logInstrumentEvent({
    required String instrumentCode,
    required String eventType,
    String? eventDetail,
    String? actor,
  }) async {
    final db = await database;
    await db.insert('instrument_history', {
      'instrument_code': instrumentCode,
      'event_type': eventType,
      'event_detail': eventDetail,
      'actor': actor,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Retrieve full history for a given instrument, newest first.
  Future<List<Map<String, dynamic>>> getInstrumentHistory(
      String instrumentCode) async {
    final db = await database;
    return await db.query(
      'instrument_history',
      where: 'instrument_code = ?',
      whereArgs: [instrumentCode],
      orderBy: 'timestamp DESC',
    );
  }

  // ── ACTIVITY LOG ─────────────────────────────────────────────────────────────

  Future<void> logActivity({
    required String eventType,
    String? eventDetail,
    String? actor,
    String? deviceInfo,
  }) async {
    try {
      final db = await database;
      await db.insert('activity_log', {
        'event_type': eventType,
        'event_detail': eventDetail,
        'actor': actor,
        'device_info': deviceInfo,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getActivityLog({int limit = 200}) async {
    try {
      final db = await database;
      return await db.query('activity_log',
          orderBy: 'timestamp DESC', limit: limit);
    } catch (_) {
      return [];
    }
  }


    // ── CONDEMN REQUESTS ─────────────────────────────────────────────────────────

  Future<void> upsertCondemnRequest({
    required String instrumentCode,
    String? instrumentName,
    String? scheduledCondemnDate,
    String? reason,
  }) async {
    try {
      final db = await database;
      await db.delete('condemn_requests',
          where: 'instrument_code = ?', whereArgs: [instrumentCode]);
      await db.insert('condemn_requests', {
        'instrument_code': instrumentCode,
        'instrument_name': instrumentName,
        'scheduled_condemn_date': scheduledCondemnDate,
        'reason': reason ?? '',
        'status': 'pending',
        'requested_at': DateTime.now().toIso8601String(),
        'responded_at': null,
      });
    } catch (_) {}
  }

  Future<int> getPendingCondemnCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM condemn_requests WHERE status = 'pending'");
      return (result.first['cnt'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingCondemnRequests() async {
    try {
      final db = await database;
      return await db.query('condemn_requests',
          where: 'status = ?',
          whereArgs: ['pending'],
          orderBy: 'requested_at DESC');
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllCondemnRequests() async {
    try {
      final db = await database;
      return await db.query('condemn_requests',
          orderBy: 'requested_at DESC');
    } catch (_) {
      return [];
    }
  }

    /// Admin approves a condemn request — updates status, then deletes instrument.
  Future<void> approveCondemnRequest(String instrumentCode) async {
    try {
      final db = await database;
      await db.update(
        'condemn_requests',
        {'status': 'approved', 'responded_at': DateTime.now().toIso8601String()},
        where: 'instrument_code = ? AND status = ?',
        whereArgs: [instrumentCode, 'pending'],
      );
      await db.delete('instruments',
          where: 'instrument_code = ?', whereArgs: [instrumentCode]);
      await db.delete('dispatch_items',
          where: 'instrument_code = ?', whereArgs: [instrumentCode]);
    } catch (_) {}
  }

  /// Admin denies a condemn request — resets instrument condition to For Repair.
  Future<void> denyCondemnRequest(String instrumentCode) async {
    try {
      final db = await database;
      await db.update(
        'instruments',
        {
          'current_condition': 'For Repair',
          'scheduled_condemn_date': null,
          'condition_edited_locally': 1,
          'schedule_edited_locally': 1,
        },
        where: 'instrument_code = ?',
        whereArgs: [instrumentCode],
      );
    } catch (_) {}
  }

   // ── INSTRUMENTS ──────────────────────────────────────────────────────────────

  Future<void> insertInstrument(Instrument instrument) async {
    final db = await database;
    await db.insert('instruments', instrument.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Upsert an instrument from the server.
  ///
  /// For NEW instruments: inserts with server data, condition_edited_locally = 0.
  /// For EXISTING instruments:
  ///   - Always updates: instrument_name, serial_number, location,
  ///     last_touch_date, last_touch_by, last_updated
  ///   - current_condition: only updated from server when condition_edited_locally == 0
  ///     (i.e. the user hasn't manually changed it since the last sync).
  ///   - status: only updated from server when there is NO pending unsynced dispatch
  ///     that involves this instrument.
  ///   - scheduled_repair_date, scheduled_condemn_date, notes: updated from server
  ///     UNLESS schedule_edited_locally == 1 (this device made the edit and hasn't
  ///     confirmed the push yet). This allows edits from OTHER devices to propagate.
  Future<void> upsertInstrumentFromServer(Instrument instrument) async {
    final db = await database;
    final existing = await db.query(
      'instruments',
      where: 'instrument_code = ?',
      whereArgs: [instrument.instrumentCode],
    );

    if (existing.isEmpty) {
      // Fresh insert — no local edits yet; accept all server values
      await db.insert('instruments', {
        ...instrument.toMap(),
        'condition_edited_locally': 0,
        'schedule_edited_locally': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await logInstrumentEvent(
        instrumentCode: instrument.instrumentCode,
        eventType: 'added',
        eventDetail: 'Instrument added to system: ${instrument.instrumentName}',
      );
      // Only alert if this is NOT the first-time sync (avoid spamming all 517 instruments on fresh install)
      final prefs = await SharedPreferences.getInstance();
      final firstSyncDone = prefs.getBool('first_sync_done') ?? false;
      if (firstSyncDone) {
        await insertInstrumentAlert(
          instrumentCode: instrument.instrumentCode,
          instrumentName: instrument.instrumentName,
          serialNumber: instrument.serialNumber,
        );
      }
      return;
    }

    final localEdited = (existing.first['condition_edited_locally'] as int?) ?? 0;
    final scheduleEdited = (existing.first['schedule_edited_locally'] as int?) ?? 0;

    // Check whether any unsynced local dispatch involves this instrument.
    final pendingRows = await db.rawQuery('''
      SELECT d.id FROM dispatches d
      JOIN dispatch_items di ON di.dispatch_id = d.id
      WHERE d.synced = 0 AND di.instrument_code = ?
      LIMIT 1
    ''', [instrument.instrumentCode]);
    final hasPendingDispatch = pendingRows.isNotEmpty;

    final Map<String, dynamic> updates = {
      'instrument_name': instrument.instrumentName,
      'serial_number': instrument.serialNumber,
      'last_touch_date': instrument.lastTouchDate,
      'last_touch_by': instrument.lastTouchBy,
      'last_updated': instrument.lastUpdated,
    };

    // Only accept server's condition when this device hasn't edited it locally.
    if (localEdited == 0) {
      updates['current_condition'] = instrument.currentCondition;
    }

    // Only accept server's status when no unsynced local dispatch is in flight.
    if (!hasPendingDispatch) {
      updates['status'] = instrument.status;
    }

    // Accept server's schedule/notes UNLESS this device was the one who edited
    // them and the push hasn't been confirmed yet (schedule_edited_locally == 1).
    // When schedule_edited_locally == 0, the server value is authoritative —
    // this allows edits made on Device A to appear on Device B after a sync.
    if (scheduleEdited == 0) {
      updates['scheduled_repair_date'] = instrument.scheduledRepairDate;
      updates['scheduled_condemn_date'] = instrument.scheduledCondemnDate;
      updates['notes'] = instrument.notes;
    }
    // Calibration fields always accept server value (no local-edit guard needed)
    if (instrument.lastCalibratedDate != null) {
      updates['last_calibrated_date'] = instrument.lastCalibratedDate;
    }
    if (instrument.calibrationNotes != null) {
      updates['calibration_notes'] = instrument.calibrationNotes;
    }

    await db.update(
      'instruments',
      updates,
      where: 'instrument_code = ?',
      whereArgs: [instrument.instrumentCode],
    );
  }

  Future<List<Instrument>> getAllInstruments() async {
    final db = await database;
    final maps = await db.query('instruments');
    return maps.map((m) => Instrument.fromMap(m)).toList();
  }

  Future<Instrument?> getInstrumentByCode(String code) async {
    final db = await database;
    final maps = await db.query('instruments',
        where: 'instrument_code = ?', whereArgs: [code]);
    if (maps.isEmpty) return null;
    return Instrument.fromMap(maps.first);
  }

  Future<void> updateInstrumentStatus(String code, String status) async {
    final db = await database;
    await db.update('instruments', {'status': status},
        where: 'instrument_code = ?', whereArgs: [code]);
  }

  Future<void> updateInstrumentCondition(String code, String condition) async {
    final db = await database;
    // Mark as locally edited so sync doesn't overwrite until pushed
    await db.update(
      'instruments',
      {
        'current_condition': condition,
        'condition_edited_locally': 1,
      },
      where: 'instrument_code = ?',
      whereArgs: [code],
    );
  }

  /// Update instrument details locally and push to the server.
  ///
  /// After a successful server PATCH, condition_edited_locally and
  /// schedule_edited_locally are reset to 0 so future syncs can accept
  /// server values (from other devices) normally.
  Future<void> updateInstrumentDetails({
    required String code,
    String? condition,
    String? conditionChangeReason,
    bool pendingAdminApproval = false,
    String? location,
    String? scheduledRepairDate,
    bool clearRepairDate = false,
    String? scheduledCondemnDate,
    bool clearCondemnDate = false,
    String? notes,
    bool clearNotes = false,
    String? lastCalibratedDate,
    String? calibrationNotes,
    String? nextCalibrationDue,
  }) async {  
    final db = await database;
    final Map<String, dynamic> updates = {};

    if (condition != null) {
      updates['current_condition'] = condition;
      // Mark condition as locally edited — sync won't overwrite until confirmed
      updates['condition_edited_locally'] = 1;
    }

    if (location != null) {
      updates['location'] = location;
    }

    // Any schedule/notes change — mark as locally edited so sync won't
    // overwrite our pending change with a stale server pull before the
    // push is confirmed.
    final bool touchingSchedule = clearRepairDate ||
        scheduledRepairDate != null ||
        clearCondemnDate ||
        scheduledCondemnDate != null ||
        clearNotes ||
        notes != null;

    if (clearRepairDate) {
      updates['scheduled_repair_date'] = null;
    } else if (scheduledRepairDate != null) {
      updates['scheduled_repair_date'] = scheduledRepairDate;
    }

    if (clearCondemnDate) {
      updates['scheduled_condemn_date'] = null;
    } else if (scheduledCondemnDate != null) {
      updates['scheduled_condemn_date'] = scheduledCondemnDate;
    }

    if (clearNotes) {
      updates['notes'] = null;
    } else if (notes != null) {
      updates['notes'] = notes;
    }

    if (touchingSchedule) {
      updates['schedule_edited_locally'] = 1;
    }

    if (lastCalibratedDate != null) {
      updates['last_calibrated_date'] = lastCalibratedDate;
    }
    if (calibrationNotes != null) {
      updates['calibration_notes'] = calibrationNotes;
    }
    if (nextCalibrationDue != null) {
      updates['next_calibration_due'] = nextCalibrationDue;
    }

    if (updates.isEmpty) return;

    // ── 1. Write to local SQLite first (always works offline) ──────────────
    await db.update('instruments', updates,
        where: 'instrument_code = ?', whereArgs: [code]);

    // ── Log history events ──────────────────────────────────────────────────
    if (condition != null) {
      final detail = conditionChangeReason != null
          ? 'Condition set to: $condition — Reason: $conditionChangeReason${pendingAdminApproval ? ' [PENDING ADMIN APPROVAL]' : ''}'
          : 'Condition set to: $condition';
      await logInstrumentEvent(
        instrumentCode: code,
        eventType: 'condition_changed',
        eventDetail: detail,
      );
    }
    if (condition == 'Condemning') {
      final inst = await getInstrumentByCode(code);
      await upsertCondemnRequest(
        instrumentCode: code,
        instrumentName: inst?.instrumentName,
        scheduledCondemnDate: scheduledCondemnDate,
        reason: conditionChangeReason,
      );
    }
    if (location != null) {
      await logInstrumentEvent(
        instrumentCode: code,
        eventType: 'location_changed',
        eventDetail: 'Location set to: $location',
      );
    }
    if (scheduledRepairDate != null) {
      await logInstrumentEvent(
        instrumentCode: code,
        eventType: 'scheduled',
        eventDetail: 'Scheduled for repair on: $scheduledRepairDate',
      );
    }
    if (scheduledCondemnDate != null) {
      await logInstrumentEvent(
        instrumentCode: code,
        eventType: 'scheduled',
        eventDetail: 'Scheduled for condemn on: $scheduledCondemnDate',
      );
    }

    // ── 2. Push to server (best-effort — fails silently when offline) ──────
    try {
      final patchBody = <String, dynamic>{};

      if (condition != null) patchBody['current_condition'] = condition;

      if (updates.containsKey('location')) {
        patchBody['location'] = updates['location'] ?? '';
      }

      if (clearRepairDate) {
        patchBody['scheduled_repair_date'] = '';
      } else if (scheduledRepairDate != null) {
        patchBody['scheduled_repair_date'] = scheduledRepairDate;
      }

      if (clearCondemnDate) {
        patchBody['scheduled_condemn_date'] = '';
      } else if (scheduledCondemnDate != null) {
        patchBody['scheduled_condemn_date'] = scheduledCondemnDate;
      }

      if (clearNotes) {
        patchBody['notes'] = '';
      } else if (notes != null) {
        patchBody['notes'] = notes;
      }

      if (lastCalibratedDate != null) {
        patchBody['last_calibrated_date'] = lastCalibratedDate;
      }
      if (calibrationNotes != null) {
        patchBody['calibration_notes'] = calibrationNotes;
      }
      if (nextCalibrationDue != null) {
        patchBody['next_calibration_due'] = nextCalibrationDue;
      }

      if (patchBody.isNotEmpty) {
        final success = await ApiService.patchInstrument(code, patchBody)
            .timeout(const Duration(seconds: 8));

        if (success) {
          // Server confirmed — clear both local-edit flags so future syncs
          // from other devices can propagate correctly.
          final flagReset = <String, dynamic>{};
          if (condition != null) flagReset['condition_edited_locally'] = 0;
          if (touchingSchedule) flagReset['schedule_edited_locally'] = 0;
          if (flagReset.isNotEmpty) {
            await db.update(
              'instruments',
              flagReset,
              where: 'instrument_code = ?',
              whereArgs: [code],
            );
          }
        }
      }
    } catch (_) {
      // Offline or server error — flags stay 1 so the next syncAll()
      // STEP 0 will retry the push and won't be overwritten by a pull.
    }
  }

  // ── ADMIN MESSAGES ────────────────────────────────────────────────────────

  Future<void> insertMessages(List<Map<String, dynamic>> messages) async {
    final db = await database;
    for (final m in messages) {
      final existing = await db.query('admin_messages',
          where: 'server_id = ?', whereArgs: [m['id']]);
      if (existing.isEmpty) {
        await db.insert('admin_messages', {
          'server_id': m['id'],
          'from_admin_id': m['from_admin_id'],
          'from_admin_name': m['from_admin_name'],
          'to_user_id': m['to_user_id'],
          'to_user_name': m['to_user_name'],
          'message': m['message'],
          'created_at': m['created_at'],
          'read_at': m['read_at'],
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> getUnreadMessages(int userId) async {
    try {
      final db = await database;
      // Fix any messages stored with null to_user_id (from old /unread bug)
      if (userId > 0) {
        await db.update(
          'admin_messages',
          {'to_user_id': userId},
          where: 'to_user_id IS NULL AND read_at IS NULL',
        );
      }
      return await db.query('admin_messages',
          where: 'to_user_id = ? AND read_at IS NULL',
          whereArgs: [userId],
          orderBy: 'created_at DESC');
    } catch (_) {
      return [];
    }
  }

  Future<void> markMessageRead(int serverId) async {
    final db = await database;
    await db.update(
      'admin_messages',
      {'read_at': DateTime.now().toIso8601String()},
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  /// Returns ALL messages for a user (read and unread), newest first.
  Future<List<Map<String, dynamic>>> getAllMessages(int userId) async {
    try {
      final db = await database;
      if (userId > 0) {
        await db.update(
          'admin_messages',
          {'to_user_id': userId},
          where: 'to_user_id IS NULL AND read_at IS NULL',
        );
      }
      return await db.query('admin_messages',
          where: 'to_user_id = ?',
          whereArgs: [userId],
          orderBy: 'created_at DESC');
    } catch (_) {
      return [];
    }
  }

  // ── NEW INSTRUMENT ALERTS ─────────────────────────────────────────────────

  Future<void> insertInstrumentAlert({
    required String instrumentCode,
    required String instrumentName,
    String? serialNumber,
  }) async {
    try {
      final db = await database;
      final existing = await db.query('new_instrument_alerts',
          where: 'instrument_code = ?', whereArgs: [instrumentCode]);
      if (existing.isEmpty) {
        await db.insert('new_instrument_alerts', {
          'instrument_code': instrumentCode,
          'instrument_name': instrumentName,
          'serial_number': serialNumber,
          'added_at': DateTime.now().toIso8601String(),
          'shown': 0,
        });
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnshownInstrumentAlerts() async {
    try {
      final db = await database;
      return await db.query('new_instrument_alerts',
          where: 'shown = ?', whereArgs: [0], orderBy: 'added_at DESC');
    } catch (_) {
      return [];
    }
  }

  Future<void> setFirstSyncDone() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyDone = prefs.getBool('first_sync_done') ?? false;
    if (!alreadyDone) {
      // On first sync only: mark all current alerts as shown to avoid spamming
      // existing instruments. Future new instruments will show alerts normally.
      final db = await database;
      await db.update('new_instrument_alerts', {'shown': 1});
      await prefs.setBool('first_sync_done', true);
    }
    // Do NOT set first_sync_done on subsequent syncs — only set it once
  }

  Future<void> markInstrumentAlertShown(int id) async {
    final db = await database;
    await db.update('new_instrument_alerts', {'shown': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Returns all instruments edited locally but not yet confirmed by the server.
  /// Covers both condition edits (condition_edited_locally) and
  /// schedule/notes edits (schedule_edited_locally).
  /// Used by SyncService STEP 0 to retry pushes after coming back online.
  Future<List<Instrument>> getLocallyEditedInstruments() async {
    final db = await database;
    final maps = await db.rawQuery(
      'SELECT * FROM instruments WHERE condition_edited_locally = 1 OR schedule_edited_locally = 1',
    );
    return maps.map((m) => Instrument.fromMap(m)).toList();
  }


  // ── CONDITION HISTORY ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getConditionHistory() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        di.instrument_code,
        di.instrument_name,
        di.current_condition   AS from_condition,
        di.return_condition    AS to_condition,
        d.date_in              AS changed_at,
        d.processed_by_name    AS changed_by,
        d.dispatch_no,
        'Return scan'          AS change_reason
      FROM dispatch_items di
      JOIN dispatches d ON di.dispatch_id = d.id
      WHERE di.return_condition IS NOT NULL
        AND di.return_condition != ''
        AND di.return_condition != di.current_condition
      ORDER BY d.date_in DESC
    ''');
    return rows;
  }

  // ── DISPATCHES ───────────────────────────────────────────────────────────────

  Future<void> insertDispatch(
      Dispatch dispatch, List<DispatchItem> items) async {
    final db = await database;
    final dispatchId = await db.insert('dispatches', dispatch.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (dispatchId == 0) return;
    for (final item in items) {
      await db.insert('dispatch_items', {
        'dispatch_id': dispatchId,
        'instrument_code': item.instrumentCode,
        'instrument_name': item.instrumentName,
        'current_condition': item.currentCondition,
        'return_condition': item.returnCondition,
        'remarks': item.remarks,
      });
      await updateInstrumentStatus(item.instrumentCode, 'In Use');
      // Log history event
      final isBorrow = dispatch.dispatchType == 'student';
      final actor = dispatch.processedByName ?? dispatch.testEngineer;
      await logInstrumentEvent(
        instrumentCode: item.instrumentCode,
        eventType: isBorrow ? 'borrowed' : 'dispatched',
        eventDetail: isBorrow
            ? 'Borrowed by ${dispatch.studentName ?? dispatch.testEngineer} (Ref: ${dispatch.dispatchNo})'
            : 'Dispatched to ${dispatch.testEngineer} (Ref: ${dispatch.dispatchNo})',
        actor: actor,
      );
    }
  }

  Future<List<Dispatch>> getAllDispatches() async {
    final db = await database;
    final maps = await db.query('dispatches', orderBy: 'id DESC');
    return maps.map((m) => Dispatch.fromMap(m)).toList();
  }

  Future<List<DispatchItem>> getDispatchItems(int dispatchId) async {
    final db = await database;
    final maps = await db.query('dispatch_items',
        where: 'dispatch_id = ?', whereArgs: [dispatchId]);
    return maps.map((m) => DispatchItem.fromMap(m)).toList();
  }

  Future<void> returnDispatch(
    int dispatchId,
    List<String> instrumentCodes, {
    Map<String, String>? returnConditions,
    List<String>? photoPaths,
    String? processedByName,
    String? dispatchNo,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final photoPathsStr =
        (photoPaths != null && photoPaths.isNotEmpty)
            ? photoPaths.join(',')
            : null;

    final Map<String, dynamic> updateMap = {
      'date_in': now,
      'synced': 0,
      'return_photo_paths': photoPathsStr,
    };
    if (processedByName != null) {
      updateMap['processed_by_name'] = processedByName;
    }

    await db.update(
      'dispatches',
      updateMap,
      where: 'id = ?',
      whereArgs: [dispatchId],
    );

    for (final code in instrumentCodes) {
      await updateInstrumentStatus(code, 'Available');
      if (returnConditions != null && returnConditions.containsKey(code)) {
        final cond = returnConditions[code]!;
        await db.update(
          'dispatch_items',
          {'return_condition': cond},
          where: 'dispatch_id = ? AND instrument_code = ?',
          whereArgs: [dispatchId, code],
        );
        // updateInstrumentCondition marks condition_edited_locally = 1
        await updateInstrumentCondition(code, cond);
        await logInstrumentEvent(
          instrumentCode: code,
          eventType: 'returned',
          eventDetail:
              'Returned with condition: $cond (Ref: ${dispatchNo ?? 'N/A'})',
          actor: processedByName,
        );
      } else {
        await logInstrumentEvent(
          instrumentCode: code,
          eventType: 'returned',
          eventDetail: 'Returned (Ref: ${dispatchNo ?? 'N/A'})',
          actor: processedByName,
        );
      }
    }
  }

  Future<List<Dispatch>> getPendingSync() async {
    final db = await database;
    final maps =
        await db.query('dispatches', where: 'synced = ?', whereArgs: [0]);
    return maps.map((m) => Dispatch.fromMap(m)).toList();
  }

  Future<void> markSynced(int dispatchId) async {
    final db = await database;
    await db.update('dispatches', {'synced': 1},
        where: 'id = ?', whereArgs: [dispatchId]);
  }

  Future<void> upsertDispatchFromServer(Map<String, dynamic> data) async {
    final db = await database;

    final existing = await db.query('dispatches',
        where: 'dispatch_no = ?', whereArgs: [data['dispatch_no']]);

    if (existing.isEmpty) {
      final dispatchId = await db.insert('dispatches', {
        'dispatch_no': data['dispatch_no'],
        'test_engineer': data['test_engineer'] ?? '',
        'processed_by_id': data['processed_by_id'] ?? 0,
        'processed_by_name': data['processed_by_name'],
        'date_out': data['date_out'] ?? '',
        'date_in': data['date_in'],
        'remarks': data['remarks'],
        'synced': 1,
        'conflict': 0,
        'dispatch_type': data['dispatch_type'] ?? 'staff',
        'student_name': data['student_name'],
        'student_id': data['student_id'],
        'student_form_photo_path': data['student_form_photo_path'],
      });

      final items = data['items'] as List<dynamic>? ?? [];
      for (final item in items) {
        await db.insert('dispatch_items', {
          'dispatch_id': dispatchId,
          'instrument_code': item['instrument_code'] ?? '',
          'instrument_name': item['instrument_name'] ?? '',
          'current_condition': item['current_condition'] ?? 'Functioning',
          'return_condition': item['return_condition'],
          'remarks': item['remarks'],
        });
        if (data['date_in'] == null) {
          await updateInstrumentStatus(
              item['instrument_code'] ?? '', 'In Use');
        }
      }
    } else {
      // Backfill items if local dispatch has none but server returned some
      final existingId = existing.first['id'] as int;
      final serverItems = data['items'] as List<dynamic>? ?? [];
      if (serverItems.isNotEmpty) {
        final localItems = await db.query('dispatch_items',
            where: 'dispatch_id = ?', whereArgs: [existingId]);
        if (localItems.isEmpty) {
          for (final item in serverItems) {
            await db.insert('dispatch_items', {
              'dispatch_id': existingId,
              'instrument_code': item['instrument_code'] ?? '',
              'instrument_name': item['instrument_name'] ?? '',
              'current_condition': item['current_condition'] ?? 'Functioning',
              'return_condition': item['return_condition'],
              'remarks': item['remarks'],
            });
          }
        }
      }
      final serverDateIn = data['date_in'];
      final localDateIn = existing.first['date_in'];
      if (serverDateIn != null && localDateIn == null) {
        await db.update(
          'dispatches',
          {'date_in': serverDateIn, 'synced': 1},
          where: 'dispatch_no = ?',
          whereArgs: [data['dispatch_no']],
        );
        final items = data['items'] as List<dynamic>? ?? [];
        for (final item in items) {
          // Server confirms return — accept server's condition since it was
          // authorised by the return flow, and clear the local-edit flag
          final returnCond = item['return_condition'] as String?;
          if (returnCond != null && returnCond.isNotEmpty) {
            await db.update(
              'instruments',
              {
                'current_condition': returnCond,
                'condition_edited_locally': 0,
              },
              where: 'instrument_code = ?',
              whereArgs: [item['instrument_code'] ?? ''],
            );
          }
          await updateInstrumentStatus(
              item['instrument_code'] ?? '', 'Available');
        }
      }
    }
  }
}