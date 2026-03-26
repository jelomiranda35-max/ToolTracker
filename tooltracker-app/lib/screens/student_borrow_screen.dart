// student_borrow_screen.dart — Build 15
//  ✅ Fix 3: Excel exports saved to /storage/emulated/0/Download/ (Downloads folder)
//  ✅ Fix 4: Export dialog now has a checkbox "Include all unreturned records (all time)"
//            When unchecked: only Sheet 1 (date range) + Summary exported
//            When checked: Sheet 2 (unreturned) is also included
//  ✅ All other behaviour preserved from Build 14

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import 'dispatch_export_screen.dart';
import '../models/dispatch.dart';
import '../models/instrument.dart';
import '../services/sync_service.dart';
import 'scanner_screen.dart';
import 'return_scanner_screen.dart';

class StudentBorrowScreen extends StatefulWidget {
  final VoidCallback onDispatchCreated;
  const StudentBorrowScreen({super.key, required this.onDispatchCreated});

  @override
  State<StudentBorrowScreen> createState() => _StudentBorrowScreenState();
}

class _StudentBorrowScreenState extends State<StudentBorrowScreen>
    with TickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  void _onFormSubmitted() {
    widget.onDispatchCreated();
    _subTabController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Builder(builder: (context) {
          final _bc = context.watch<ThemeNotifier>().colors;
          return Container(
          color: _bc.surfaceVariant,
          child: TabBar(
            controller: _subTabController,
            indicatorColor: Colors.purple,
            indicatorWeight: 2,
            labelColor: Colors.purple,
            unselectedLabelColor: _bc.textHint,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(text: 'Records'),
              Tab(text: 'New Borrow'),
            ],
          ),
        );
        }),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _StudentRecordsSubTab(
                  onReturnComplete: widget.onDispatchCreated),
              _StudentBorrowFormSubTab(onSubmitted: _onFormSubmitted),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUB-TAB A — STUDENT RECORDS
// ══════════════════════════════════════════════════════════════════════════════

class _StudentRecordsSubTab extends StatefulWidget {
  final VoidCallback onReturnComplete;
  const _StudentRecordsSubTab({required this.onReturnComplete});

  @override
  State<_StudentRecordsSubTab> createState() => _StudentRecordsSubTabState();
}

class _StudentRecordsSubTabState extends State<_StudentRecordsSubTab> {
  List<Dispatch> _records = [];
  List<Dispatch> _filtered = [];
  String _statusFilter = 'all';
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (await SyncService.isConnected()) {
        await SyncService.instance
            .syncAll()
            .timeout(const Duration(seconds: 15));
      }
    } catch (_) {}

    try {
      final all = await DBHelper.instance.getAllDispatches();
      if (mounted) {
        setState(() {
          _records = all.where((d) => d.isStudent).toList();
          _applyFilter();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
    void _applyFilter() {
    switch (_statusFilter) {
      case 'out':
        _filtered = _records.where((d) => d.dateIn == null).toList();
        break;
      case 'returned':
        _filtered = _records.where((d) => d.dateIn != null).toList();
        break;
      default:
        _filtered = List.from(_records);
    }
  }

  void _setFilter(String f) {
    setState(() {
      _statusFilter = f;
      _applyFilter();
    });
  }

  String _formatDate(String? s) {
    if (s == null) return '—';
    try {
      return DateFormat('MMM dd, yyyy  hh:mm a').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  String _fmtShort(String? s) {
    if (s == null) return '—';
    try {
      final d = DateTime.parse(s);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  // FIX 3: Get Downloads folder path
  Future<String> _getDownloadsPath() async {
    const downloadsPath = '/storage/emulated/0/Download';
    try {
      final dir = Directory(downloadsPath);
      if (await dir.exists()) return downloadsPath;
    } catch (_) {}
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext.path;
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  // FIX 4: Export dialog now includes checkbox for unreturned records
  Future<void> _showExportDialog() async {
    bool exportOut = true;
    bool exportReturned = true;
    DateTime? fromDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 32 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('EXPORT BORROW RECORDS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('DATE RANGE',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: fromDate ?? DateTime.now().subtract(const Duration(days: 30)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (c, child) => Theme(
                      data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                              primary: Color(0xFFF5A623),
                              onPrimary: Colors.black,
                              surface: Color(0xFF1A3A5C))),
                      child: child!,
                    ),
                  );
                  if (picked != null) setModalState(() => fromDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: fromDate != null
                        ? const Color(0xFFF5A623).withValues(alpha: 0.08)
                        : const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: fromDate != null
                            ? const Color(0xFFF5A623)
                            : const Color(0xFF1E3A5F)),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        color: fromDate != null ? const Color(0xFFF5A623) : Colors.white38,
                        size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fromDate != null
                            ? 'From: ${fromDate!.day}/${fromDate!.month}/${fromDate!.year}  →  Today'
                            : 'Tap to set start date (defaults to all time)',
                        style: TextStyle(
                            color: fromDate != null ? const Color(0xFFF5A623) : Colors.white38,
                            fontSize: 13),
                      ),
                    ),
                    if (fromDate != null)
                      GestureDetector(
                        onTap: () => setModalState(() => fromDate = null),
                        child: const Icon(Icons.close, color: Colors.white38, size: 16),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              const Text('INCLUDE RECORDS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              CheckboxListTile(
                dense: true,
                value: exportOut,
                activeColor: const Color(0xFFF5A623),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                title: const Row(children: [
                  Icon(Icons.outbox, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Text('Currently Active (not yet returned)',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
                onChanged: (v) => setModalState(() => exportOut = v!),
              ),
              CheckboxListTile(
                dense: true,
                value: exportReturned,
                activeColor: const Color(0xFFF5A623),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                title: const Row(children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text('Returned',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
                onChanged: (v) => setModalState(() => exportReturned = v!),
              ),
              const SizedBox(height: 12),
              if (!exportOut && !exportReturned)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Select at least one option.',
                      style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (!exportOut && !exportReturned)
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DispatchExportScreen(
                                exportType: ExportType.borrow,
                                exportOut: exportOut,
                                exportReturned: exportReturned,
                                dispatchFromDate: fromDate,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT TO EXCEL',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSet ? Colors.purple.withOpacity(0.1) : const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSet ? Colors.purple : const Color(0xFF1E3A5F)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today,
              color: isSet ? Colors.purple : Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: isSet ? Colors.purple : Colors.white38,
                      fontSize: 14,
                      fontWeight:
                          isSet ? FontWeight.bold : FontWeight.normal))),
          if (onClear != null)
            GestureDetector(
                onTap: onClear,
                child:
                    const Icon(Icons.close, color: Colors.white38, size: 18)),
        ]),
      ),
    );
  }


    setState(() => _exporting = true);
    try {
      final fromStart = DateTime(from.year, from.month, from.day, 0, 0, 0);
      final toEnd = DateTime(to.year, to.month, to.day, 23, 59, 59);

      final Map<int, List<DispatchItem>> itemsMap = {};
      for (final d in _records) {
        if (d.id != null) {
          itemsMap[d.id!] = await DBHelper.instance.getDispatchItems(d.id!);
        }
      }

      final inRange = _records.where((d) {
        try {
          final dateOut = DateTime.parse(d.dateOut);
          return dateOut.isAfter(fromStart) && dateOut.isBefore(toEnd);
        } catch (_) {
          return false;
        }
      }).toList();

      // FIX 4: unreturned list only needed if checkbox was checked
      final unreturned = includeUnreturned
          ? _records.where((d) => d.dateIn == null).toList()
          : <Dispatch>[];

      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final now = DateTime.now();
      final dateRangeStr =
          '${_fmtShort(from.toIso8601String())} – ${_fmtShort(to.toIso8601String())}';

      // ── Sheet 1: Borrowed in range ───────────────────────────────────────
      final sheet1 = excel['Borrowed (${_fmtShort(from.toIso8601String())} to ${_fmtShort(to.toIso8601String())})'];
      _writeHeaders(sheet1, [
        'Transaction No.',
        'Borrower Name',
        'Borrower ID',
        'Contact Number',
        'Email',
        'Purpose',
        'Processed By',
        'Date Borrowed',
        'Date Returned',
        'Status',
        'Instruments Borrowed',
        'Instrument Barcodes',
        'Remarks',
        'Form Photo Path',
      ]);
      for (final d in inRange) {
        final items = itemsMap[d.id] ?? [];
        final instrumentNames = items.map((i) => i.instrumentName).join(', ');
        final instrumentCodes = items.map((i) => i.instrumentCode).join(', ');
        final status = d.dateIn == null ? 'NOT RETURNED' : 'Returned';
        sheet1.appendRow([
          TextCellValue(d.dispatchNo),
          TextCellValue(d.studentName ?? d.testEngineer),
          TextCellValue(d.studentId ?? '—'),
          TextCellValue(d.borrowerContact ?? '—'),
          TextCellValue(d.borrowerEmail ?? '—'),
          TextCellValue(d.borrowerPurpose ?? '—'),
          TextCellValue(d.processedByName ?? '—'),
          TextCellValue(_formatDate(d.dateOut)),
          TextCellValue(_formatDate(d.dateIn)),
          TextCellValue(status),
          TextCellValue(instrumentNames),
          TextCellValue(instrumentCodes),
          TextCellValue(d.remarks ?? ''),
          TextCellValue(d.studentFormPhotoPath ?? ''),
        ]);
        if (d.dateIn == null) {
          for (int c = 0; c < 14; c++) {
            final rowIndex = sheet1.maxRows - 1;
            final cell = sheet1.cell(
                CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
            cell.cellStyle = CellStyle(
                fontColorHex: ExcelColor.fromHexString('#FF4444'));
          }
        }
      }
      sheet1.setColumnWidth(0, 22);   // Transaction No.
      sheet1.setColumnWidth(1, 24);   // Borrower Name
      sheet1.setColumnWidth(2, 18);   // Borrower ID
      sheet1.setColumnWidth(3, 20);   // Contact Number
      sheet1.setColumnWidth(4, 28);   // Email
      sheet1.setColumnWidth(5, 32);   // Purpose
      sheet1.setColumnWidth(6, 20);   // Processed By
      sheet1.setColumnWidth(7, 24);   // Date Borrowed
      sheet1.setColumnWidth(8, 24);   // Date Returned
      sheet1.setColumnWidth(9, 16);   // Status
      sheet1.setColumnWidth(10, 36);  // Instruments Borrowed
      sheet1.setColumnWidth(11, 32);  // Instrument Barcodes
      sheet1.setColumnWidth(12, 24);  // Remarks
      sheet1.setColumnWidth(13, 40);  // Form Photo Path

      // FIX 4: Sheet 2 only included when user checked the box
      if (includeUnreturned) {
        final sheet2 = excel['Unreturned Instruments'];
        _writeHeaders(sheet2, [
          'Transaction No.',
          'Borrower Name',
          'Borrower ID',
          'Contact Number',
          'Email',
          'Purpose',
          'Processed By',
          'Date Borrowed',
          'Days Outstanding',
          'Instruments NOT Returned',
          'Instrument Barcodes',
          'Remarks',
        ]);
        for (final d in unreturned) {
          final items = itemsMap[d.id] ?? [];
          final instrumentNames = items.map((i) => i.instrumentName).join(', ');
          final instrumentCodes = items.map((i) => i.instrumentCode).join(', ');
          int daysOut = 0;
          try {
            daysOut = DateTime.now().difference(DateTime.parse(d.dateOut)).inDays;
          } catch (_) {}
          sheet2.appendRow([
            TextCellValue(d.dispatchNo),
            TextCellValue(d.studentName ?? d.testEngineer),
            TextCellValue(d.studentId ?? '—'),
            TextCellValue(d.borrowerContact ?? '—'),
            TextCellValue(d.borrowerEmail ?? '—'),
            TextCellValue(d.borrowerPurpose ?? '—'),
            TextCellValue(d.processedByName ?? '—'),
            TextCellValue(_formatDate(d.dateOut)),
            TextCellValue('$daysOut days'),
            TextCellValue(instrumentNames),
            TextCellValue(instrumentCodes),
            TextCellValue(d.remarks ?? ''),
          ]);
        }
        sheet2.setColumnWidth(0, 22);   // Transaction No.
        sheet2.setColumnWidth(1, 24);   // Borrower Name
        sheet2.setColumnWidth(2, 18);   // Borrower ID
        sheet2.setColumnWidth(3, 20);   // Contact Number
        sheet2.setColumnWidth(4, 28);   // Email
        sheet2.setColumnWidth(5, 32);   // Purpose
        sheet2.setColumnWidth(6, 20);   // Processed By
        sheet2.setColumnWidth(7, 24);   // Date Borrowed
        sheet2.setColumnWidth(8, 18);   // Days Outstanding
        sheet2.setColumnWidth(9, 36);   // Instruments NOT Returned
        sheet2.setColumnWidth(10, 32);  // Instrument Barcodes
        sheet2.setColumnWidth(11, 24);  // Remarks
      }

      // Summary
      final summary = excel['Summary'];
      final summaryRows = [
        ['AMTEC Tool Tracker — Borrower Records Export', ''],
        ['', ''],
        ['Export Date', DateFormat('MMMM dd, yyyy  hh:mm a').format(now)],
        ['Date Range', dateRangeStr],
        ['', ''],
        ['SHEET 1: Borrowed in Range', ''],
        ['Total Records', '${inRange.length}'],
        ['Returned', '${inRange.where((d) => d.dateIn != null).length}'],
        ['Not Yet Returned', '${inRange.where((d) => d.dateIn == null).length}'],
        if (includeUnreturned) ...[
          ['', ''],
          ['SHEET 2: Unreturned (All Time)', ''],
          ['Total Unreturned', '${unreturned.length}'],
        ],
      ];
      for (final r in summaryRows) {
        summary.appendRow(r.map((v) => TextCellValue(v)).toList());
      }
      summary.setColumnWidth(0, 34);
      summary.setColumnWidth(1, 22);

      // FIX 3: Save to Downloads folder
      final dirPath = await _getDownloadsPath();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filePath = '$dirPath/AMTEC_StudentBorrow_$timestamp.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');
      await File(filePath).writeAsBytes(bytes);

      setState(() => _exporting = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A3A5C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 22),
              SizedBox(width: 8),
              Text('Export Complete',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date range: $dateRangeStr',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Text('${inRange.length} borrowed records exported',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                if (includeUnreturned)
                  Text('${unreturned.length} unreturned records included',
                      style: const TextStyle(color: Colors.orange, fontSize: 12)),
                const SizedBox(height: 8),
                const Text('Saved to Downloads folder:',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text(filePath.split('/').last,
                    style: const TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white),
                child: const Text('OK',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _exporting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  void _writeHeaders(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#3B0764'),
        fontColorHex: ExcelColor.fromHexString('#E9D5FF'),
      );
    }
  }

  void _showDetail(Dispatch d) async {
    final items = await DBHelper.instance.getDispatchItems(d.id!);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99)))),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple)),
                  child: const Text('BORROWER',
                      style: TextStyle(
                          color: Colors.purple,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(d.dispatchNo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18))),
                _badge(d.dateIn == null ? 'Out' : 'Returned'),
              ]),
              const SizedBox(height: 16),
              _dRow(Icons.person, 'Borrower Name', d.studentName ?? '—'),
              _dRow(Icons.badge, 'Borrower ID', d.studentId ?? '—'),
              if (d.borrowerContact != null && d.borrowerContact!.isNotEmpty)
                _dRow(Icons.phone, 'Contact No.', d.borrowerContact!),
              if (d.borrowerEmail != null && d.borrowerEmail!.isNotEmpty)
                _dRow(Icons.email, 'Email', d.borrowerEmail!),
              if (d.borrowerPurpose != null && d.borrowerPurpose!.isNotEmpty)
                _dRow(Icons.assignment, 'Purpose', d.borrowerPurpose!),
              if (d.processedByName != null && d.processedByName!.isNotEmpty)
                _dRow(Icons.person, 'Processed By', d.processedByName!),
              _dRow(Icons.logout, 'Date Out', _formatDate(d.dateOut)),
              _dRow(Icons.login, 'Date In', _formatDate(d.dateIn)),
              if (d.remarks != null && d.remarks!.isNotEmpty)
                _dRow(Icons.notes, 'Remarks', d.remarks!),
              if (d.studentFormPhotoPath != null) ...[
                const SizedBox(height: 16),
                const Text('BORROWING FORM PHOTO',
                    style: TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 10,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _viewPhoto(d.studentFormPhotoPath!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(d.studentFormPhotoPath!),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 80,
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.white38)),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (d.dateIn == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final dispatchItems =
                          await DBHelper.instance.getDispatchItems(d.id!);
                      if (!mounted) return;
                      Navigator.pop(context);
                      final returned = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ReturnScannerScreen(
                                dispatch: d, items: dispatchItems)),
                      );
                      if (returned == true) {
                        _load();
                        widget.onReturnComplete();
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('RETURN INSTRUMENTS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text('INSTRUMENTS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('No instruments data.',
                    style: TextStyle(color: Colors.white38, fontSize: 12))
              else
                ...items.map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0D1B2A),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: const Color(0xFF1E3A5F))),
                      child: Row(children: [
                        const Icon(Icons.build,
                            color: Colors.purple, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item.instrumentName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text(
                                  '${item.instrumentCode} · ${item.currentCondition}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                              if (item.returnCondition != null &&
                                  item.returnCondition!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                    'Returned: ${item.returnCondition}',
                                    style: TextStyle(
                                      color: item.returnCondition ==
                                              'Functioning'
                                          ? Colors.green
                                          : item.returnCondition ==
                                                  'For Repair'
                                              ? Colors.orange
                                              : Colors.red,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    )),
                              ],
                            ])),
                      ]),
                    )),
              if (d.returnPhotoPaths.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('RETURN PHOTOS',
                    style: TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: d.returnPhotoPaths.map((path) {
                      return GestureDetector(
                        onTap: () => _viewPhoto(path),
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFF5A623)
                                      .withOpacity(0.4)),
                              image: DecorationImage(
                                  image: FileImage(File(path)),
                                  fit: BoxFit.cover)),
                          child: Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                  margin: const EdgeInsets.all(4),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(4)),
                                  child: const Icon(Icons.zoom_in,
                                      color: Colors.white, size: 12))),
                        ),
                      );
                    }).toList()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewPhoto(String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
              child: Image.file(File(path),
                  fit: BoxFit.contain, width: double.infinity)),
          Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(99)),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20)))),
        ]),
      ),
    );
  }

  Widget _badge(String status) {
    final isOut = status == 'Out';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOut
            ? Colors.orange.withOpacity(0.15)
            : Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: isOut ? Colors.orange : Colors.green),
      ),
      child: Text(status,
          style: TextStyle(
              color: isOut ? Colors.orange : Colors.green,
              fontSize: 11,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _dRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.purple, size: 15),
          const SizedBox(width: 8),
          SizedBox(
              width: 100,
              child: Text('$label:',
                  style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
      );

Widget _filterChip(String label, int count, String filter, Color color) {
    final selected = _statusFilter == filter;
    return GestureDetector(
      onTap: () => _setFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? color : const Color(0xFF1E3A5F),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: selected ? color : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.25) : const Color(0xFF1E3A5F),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: selected ? color : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outCount = _records.where((d) => d.dateIn == null).length;
    final returnedCount = _records.where((d) => d.dateIn != null).length;

    return _loading
        ? const Center(
            child: CircularProgressIndicator(color: Colors.purple))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _filterChip('All', _records.length, 'all', Colors.purple),
                          const SizedBox(width: 8),
                          _filterChip('Out', outCount, 'out', Colors.orange),
                          const SizedBox(width: 8),
                          _filterChip('Returned', returnedCount, 'returned', Colors.green),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        onPressed:
                            _records.isEmpty || _exporting ? null : _showExportDialog,
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.purple))
                        : const Icon(Icons.file_download,
                            color: Colors.purple, size: 18),
                    label: Text(
                      _exporting ? 'Exporting...' : 'Export to Excel',
                      style: const TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold),
                    ),
style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: const BorderSide(color: Colors.purple),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_filtered.length} record${_filtered.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school,
                                  color: Colors.white24, size: 48),
                              SizedBox(height: 12),
                              Text('No student borrow records yet',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 13)),
                              SizedBox(height: 4),
                              Text(
                                  'Use "New Borrow" tab to record a new session',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 11)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final d = _filtered[i];
                            final isOut = d.dateIn == null;
                            return GestureDetector(
                              onTap: () => _showDetail(d),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A3A5C),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: isOut
                                          ? Colors.purple.withOpacity(0.5)
                                          : const Color(0xFF1E3A5F)),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.school,
                                        color: Colors.purple, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            d.studentName ?? d.testEngineer,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        Text('ID: ${d.studentId ?? '—'}',
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11)),
                                        Text(_formatDate(d.dateOut),
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11)),
                                      ])),
                                  Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        _badge(isOut ? 'Out' : 'Returned'),
                                        const SizedBox(height: 4),
                                        Text(d.dispatchNo,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10)),
                                      ]),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUB-TAB B — NEW STUDENT BORROW FORM  (unchanged from Build 14)
// ══════════════════════════════════════════════════════════════════════════════

class _StudentBorrowFormSubTab extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _StudentBorrowFormSubTab({required this.onSubmitted});

  @override
  State<_StudentBorrowFormSubTab> createState() =>
      _StudentBorrowFormSubTabState();
}

class _StudentBorrowFormSubTabState extends State<_StudentBorrowFormSubTab> {
  int _step = 0;

  final List<String> _formPhotoPaths = [];
  final ImagePicker _picker = ImagePicker();

  final _studentNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _dispatchNoCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  final List<DispatchItem> _scannedItems = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prefillDispatchNo();
  }

  @override
  void dispose() {
    _studentNameCtrl.dispose();
    _studentIdCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _purposeCtrl.dispose();
    _dispatchNoCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillDispatchNo() async {
    final now = DateTime.now();
    final db = await DBHelper.instance.database;
    // Count existing borrow dispatches this year to get sequential number
    final yearPrefix = 'IBF-${now.year}-';
    final existing = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM dispatches WHERE dispatch_no LIKE ? AND dispatch_type = 'student'",
      ['$yearPrefix%'],
    );
    final count = (existing.first['cnt'] as int? ?? 0) + 1;
    final seq = count.toString().padLeft(4, '0');
    setState(() => _dispatchNoCtrl.text = '$yearPrefix$seq');
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo == null) return;
      setState(() => _formPhotoPaths.add(photo.path));
    } catch (e) {
      if (mounted) _snack('Could not open camera: $e', Colors.red);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (photo == null) return;
      setState(() => _formPhotoPaths.add(photo.path));
    } catch (e) {
      if (mounted) _snack('Could not open gallery: $e', Colors.red);
    }
  }

  void _removePhoto(int index) =>
      setState(() => _formPhotoPaths.removeAt(index));
  void _skipPhoto() => setState(() => _step = 1);

  void _goToScan() {
    if (_studentNameCtrl.text.trim().isEmpty) {
      _snack('Please enter the borrower name', Colors.red);
      return;
    }
    if (_studentIdCtrl.text.trim().isEmpty) {
      _snack('Please enter the borrower ID number', Colors.red);
      return;
    }
    if (_dispatchNoCtrl.text.trim().isEmpty) {
      _snack('Please enter a transaction number', Colors.red);
      return;
    }
    setState(() => _step = 2);
  }

  Future<void> _scanInstrument() async {
    final instrument = await Navigator.push<Instrument>(
      context,
      MaterialPageRoute(
          builder: (_) => const ScannerScreen(mode: ScannerMode.borrow)),
    );
    if (instrument == null) return;
    if (_scannedItems
        .any((i) => i.instrumentCode == instrument.instrumentCode)) {
      _snack('Already added', Colors.orange);
      return;
    }
    setState(() {
      _scannedItems.add(DispatchItem(
        instrumentCode: instrument.instrumentCode,
        instrumentName: instrument.instrumentName,
        currentCondition: 'Functioning',
      ));
    });
  }

  Future<void> _submit() async {
    if (_scannedItems.isEmpty) {
      _snack('Please scan at least one instrument', Colors.red);
      return;
    }
    setState(() => _submitting = true);
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 1;
    final userName = prefs.getString('user_name') ?? '';

    try {
      final dispatch = Dispatch(
        dispatchNo: _dispatchNoCtrl.text.trim(),
        testEngineer: _studentNameCtrl.text.trim(),
        processedById: userId,
        processedByName: userName,
        dateOut: DateTime.now().toIso8601String(),
        remarks: _remarksCtrl.text.trim().isEmpty
            ? null
            : _remarksCtrl.text.trim(),
        dispatchType: 'student',
        studentName: _studentNameCtrl.text.trim(),
        studentId: _studentIdCtrl.text.trim(),
        studentFormPhotoPath:
            _formPhotoPaths.isNotEmpty ? _formPhotoPaths.first : null,
        borrowerContact: _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
        borrowerEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        borrowerPurpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
      );

      await DBHelper.instance.insertDispatch(dispatch, _scannedItems);
      await DBHelper.instance.logActivity(
        eventType: 'borrow_created',
        eventDetail: 'Borrow ${dispatch.dispatchNo} — ${_studentNameCtrl.text.trim()} (${_studentIdCtrl.text.trim()})',
        actor: userName,
      );

      if (mounted) {
        widget.onSubmitted();
        setState(() {
          _step = 0;
          _formPhotoPaths.clear();
          _studentNameCtrl.clear();
          _studentIdCtrl.clear();
          _contactCtrl.clear();
          _emailCtrl.clear();
          _purposeCtrl.clear();
          _remarksCtrl.clear();
          _scannedItems.clear();
          _submitting = false;
          _prefillDispatchNo();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.school, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Student Borrow Session saved',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          backgroundColor: Colors.purple.shade700,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        String msg = 'Failed to create record.';
        if (e.toString().toLowerCase().contains('unique')) {
          msg = 'Transaction No. already exists. Use a different number.';
        }
        _snack(msg, Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeNotifier>().colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _step > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: colors.accent),
                onPressed: () => setState(() => _step--),
              )
            : null,
        title: Text(
          ['Step 1: Capture Form', 'Step 2: Borrower Info', 'Step 3: Scan Instruments'][_step],
          style: TextStyle(
              color: colors.accent, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(child: _buildStep()),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    final colors = context.watch<ThemeNotifier>().colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: colors.surfaceVariant,
      child: Row(
        children: List.generate(3, (i) {
          final active = _step == i;
          final done = _step > i;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: (active || done) ? Colors.purple : colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildPhotoStep();
      case 1: return _buildInfoStep();
      case 2: return _buildScanStep();
      default: return const SizedBox();
    }
  }

  Widget _buildPhotoStep() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 200),
            width: double.infinity,
            color: context.watch<ThemeNotifier>().colors.surface,
            child: _formPhotoPaths.isEmpty
                ? const SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.document_scanner, color: Colors.white24, size: 72),
                        SizedBox(height: 12),
                        Text('No photos yet', style: TextStyle(color: Colors.white38, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Take or upload photos of the borrowing form',
                            style: TextStyle(color: Colors.white24, fontSize: 11),
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_formPhotoPaths.length} photo${_formPhotoPaths.length != 1 ? 's' : ''} added',
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(
                              _formPhotoPaths.length,
                              (i) => Stack(children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(File(_formPhotoPaths[i]),
                                          width: 90, height: 90, fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: GestureDetector(
                                        onTap: () => _removePhoto(i),
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                              color: Colors.red, shape: BoxShape.circle),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 12),
                                        ),
                                      ),
                                    ),
                                  ])),
                        ),
                      ],
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            color: context.watch<ThemeNotifier>().colors.surfaceVariant,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BORROW INSTRUMENT',
                    style: TextStyle(color: Color(0xFFF5A623), fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Record instruments borrowed by students or staff',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 16),
                const Text('Optionally capture the physical borrowing form. You can add multiple photos.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt, color: Colors.black),
                    label: const Text('Take Photo of Form',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5A623),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library, color: Color(0xFFF5A623)),
                    label: const Text('Upload from Gallery',
                        style: TextStyle(color: Color(0xFFF5A623))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFF5A623)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_formPhotoPaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => setState(() => _step = 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                          'NEXT  (${_formPhotoPaths.length} photo${_formPhotoPaths.length != 1 ? 's' : ''} added)',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _skipPhoto,
                    child: const Text('Skip — proceed without photo',
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_formPhotoPaths.isNotEmpty) ...[
            _label('FORM PHOTOS (${_formPhotoPaths.length})'),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _formPhotoPaths.length,
                itemBuilder: (_, i) => Stack(children: [
                  Container(
                    width: 90,
                    height: 82,
                    margin: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_formPhotoPaths[i]), fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                      top: 2,
                      right: 10,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _formPhotoPaths.removeAt(i);
                            if (_formPhotoPaths.isEmpty) _step = 0;
                          });
                        },
                        child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 11)),
                      )),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: context.watch<ThemeNotifier>().colors.cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.watch<ThemeNotifier>().colors.border)),
              child: Row(children: [
                Icon(Icons.info_outline, color: context.watch<ThemeNotifier>().colors.textHint, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('No form photo — tap back to add.',
                        style: TextStyle(color: context.watch<ThemeNotifier>().colors.textHint, fontSize: 11))),
              ]),
            ),
          _label('BORROWER INFORMATION'),
          const SizedBox(height: 10),
          _field(_studentNameCtrl, 'Borrower Full Name', Icons.person),
          const SizedBox(height: 10),
          _field(_studentIdCtrl, 'Borrower ID Number', Icons.badge),
          const SizedBox(height: 10),
          _field(_contactCtrl, 'Contact Number', Icons.phone),
          const SizedBox(height: 10),
          _field(_emailCtrl, 'Email Address (optional)', Icons.email),
          const SizedBox(height: 10),
          _field(_purposeCtrl, 'Purpose of Borrowing', Icons.assignment),
          const SizedBox(height: 20),
          _label('TRANSACTION DETAILS'),
          const SizedBox(height: 10),
          _field(_dispatchNoCtrl, 'Transaction No.', Icons.tag),
          const SizedBox(height: 10),
          _field(_remarksCtrl, 'Remarks (optional)', Icons.notes),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _goToScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('NEXT: SCAN INSTRUMENTS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanStep() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.watch<ThemeNotifier>().colors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.withOpacity(0.4)),
          ),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.school, color: Colors.purple, size: 22)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_studentNameCtrl.text,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('ID: ${_studentIdCtrl.text}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  if (_purposeCtrl.text.isNotEmpty)
                    Text('Purpose: ${_purposeCtrl.text}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  Text(_dispatchNoCtrl.text,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ])),
            if (_formPhotoPaths.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purple.withOpacity(0.5))),
                child: Text(
                    '${_formPhotoPaths.length} photo${_formPhotoPaths.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: Colors.purple, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _scanInstrument,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.purple),
              label: const Text('Scan Instrument', style: TextStyle(color: Colors.purple)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.purple),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _scannedItems.isEmpty
              ? const Center(
                  child: Text('No instruments scanned yet',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _scannedItems.length,
                  itemBuilder: (_, i) {
                    final item = _scannedItems[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFF1A3A5C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.withOpacity(0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.purple, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item.instrumentName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              Text(item.instrumentCode,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                            ])),
                        IconButton(
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red, size: 18),
                            onPressed: () =>
                                setState(() => _scannedItems.removeAt(i))),
                      ]),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      'CONFIRM BORROW  (${_scannedItems.length} item${_scannedItems.length != 1 ? 's' : ''})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Color(0xFFF5A623), fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold));

  Widget _field(TextEditingController c, String label, IconData icon) => TextField(
        controller: c,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38),
          prefixIcon: Icon(icon, color: Colors.purple),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.purple)),
          filled: true,
          fillColor: const Color(0xFF1A3A5C),
        ),
      );
}