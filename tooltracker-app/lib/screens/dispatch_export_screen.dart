// dispatch_export_screen.dart — Build 16
//  ✅ Now accepts exportOut / exportReturned flags from DispatchRecordsTab export dialog

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/dispatch.dart';
import '../models/instrument.dart';

enum ExportType { dispatch, borrow, conditionHistory, upcoming, overdue, forRepair, forCondemn, instrumentsOut }

class DispatchExportScreen extends StatefulWidget {
  final ExportType exportType;
  final List<ExportType>? multiExportTypes;
  final bool exportOut;
  final bool exportReturned;
  // New params from admin export menu
  final DateTime? dispatchFromDate;
  final bool? dispatchActiveOnly;
  final bool? dispatchReturnedOnly;
  final DateTime? condHistoryFromDate;
  final bool? condHistoryByDate;

  const DispatchExportScreen({
    super.key,
    this.exportType = ExportType.dispatch,
    this.multiExportTypes,
    this.exportOut = true,
    this.exportReturned = true,
    this.dispatchFromDate,
    this.dispatchActiveOnly,
    this.dispatchReturnedOnly,
    this.condHistoryFromDate,
    this.condHistoryByDate,
  });

  @override
  State<DispatchExportScreen> createState() => _DispatchExportScreenState();
}

class _DispatchExportScreenState extends State<DispatchExportScreen> {
  bool _loading = false;
  DateTime? _fromDate;
  DateTime? _toDate;
  List<String> _allInstrumentCodes = [];
  Map<String, String> _codeToName = {}; // instrument_code -> instrument_name
  List<String> _selectedCodes = [];
  String _codeSearch = '';
  // true = filter by date range, false = select instruments individually
  late bool _useByDate;

  @override
  void initState() {
    super.initState();
    // Use the param from admin export menu; default to true (by date)
    _useByDate = widget.condHistoryByDate ?? true;
    // Pre-apply condHistoryFromDate if provided
    if (widget.condHistoryFromDate != null) {
      _fromDate = widget.condHistoryFromDate;
      _toDate = DateTime.now();
    }
    if (widget.exportType == ExportType.conditionHistory ||
        (widget.multiExportTypes?.contains(ExportType.conditionHistory) ?? false)) {
      _loadInstrumentCodes();
    }
  }

  Future<void> _loadInstrumentCodes() async {
    final instruments = await DBHelper.instance.getAllInstruments();
    instruments.sort((a, b) => a.instrumentName.compareTo(b.instrumentName));
    final codes = instruments.map((i) => i.instrumentCode).toList();
    final nameMap = {for (final i in instruments) i.instrumentCode: i.instrumentName};
    if (mounted) setState(() {
      _allInstrumentCodes = codes;
      _codeToName = nameMap;
      _selectedCodes = List.from(codes);
    });
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

  String _fmtLong(String? s) {
    if (s == null) return '—';
    try {
      return DateFormat('MMM dd, yyyy  hh:mm a').format(DateTime.parse(s));
    } catch (_) {
      return s;
    }
  }

  Future<String> _getDownloadsPath() async {
    // Try the public Downloads folder first (works on Android < 10 or with MANAGE_EXTERNAL_STORAGE)
    const downloadsPath = '/storage/emulated/0/Download';
    try {
      final dir = Directory(downloadsPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      // Test write access
      final testFile = File('$downloadsPath/.write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return downloadsPath;
    } catch (_) {}
    // Fallback: external app storage (always writable, shows in Files app)
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        if (!await ext.exists()) await ext.create(recursive: true);
        return ext.path;
      }
    } catch (_) {}
    // Final fallback: internal app documents
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  Future<void> _exportSimpleInstrumentList({
    required String title,
    required String fileName,
    required List<Instrument> instruments,
    List<String>? extraHeaders,
    List<String> Function(Instrument)? extraCells,
  }) async {
    setState(() => _loading = true);
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['Instruments'];
      final now = DateTime.now();

      sheet.appendRow([TextCellValue(title)]);
      sheet.appendRow([TextCellValue('Export Date'),
          TextCellValue(DateFormat('MMMM dd, yyyy  hh:mm a').format(now))]);
      sheet.appendRow([TextCellValue('')]);

      final headers = [
        'Instrument Code', 'Instrument Name', 'Serial Number',
        'Condition', 'Status', 'Location',
        ...?extraHeaders,
      ];
      final headerRow = sheet.maxRows;
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
      final hStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1A3A5C'),
        fontColorHex: ExcelColor.fromHexString('#F5A623'),
      );
      for (int c = 0; c < headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRow)).cellStyle = hStyle;
      }

      for (final i in instruments) {
        sheet.appendRow([
          TextCellValue(i.instrumentCode),
          TextCellValue(i.instrumentName),
          TextCellValue(i.serialNumber ?? '—'),
          TextCellValue(i.currentCondition),
          TextCellValue(i.status),
          TextCellValue(i.location ?? '—'),
          ...?(extraCells?.call(i).map((v) => TextCellValue(v)).toList()),
        ]);
      }

      sheet.setColumnWidth(0, 16);
      sheet.setColumnWidth(1, 26);
      sheet.setColumnWidth(2, 18);
      sheet.setColumnWidth(3, 16);
      sheet.setColumnWidth(4, 14);
      sheet.setColumnWidth(5, 18);

      final downloadsPath = await _getDownloadsPath();
      final file = File('$downloadsPath/${fileName}_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx');
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Encode failed');
      await file.writeAsBytes(bytes);

      if (mounted) _showSuccessDialog(file.path.split('/').last);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessDialog(String fileName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 22),
          SizedBox(width: 8),
          Text('Export Complete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        content: Text(fileName,
            style: const TextStyle(
                color: Color(0xFFF5A623),
                fontSize: 13,
                fontWeight: FontWeight.bold)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBorrow() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select both From and To dates'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() => _loading = true);
    try {
      final fromStart = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final toEnd = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
      final allDispatches = await DBHelper.instance.getAllDispatches();
      final borrowDispatches = allDispatches.where((d) => d.isStudent).toList();
      final inRange = borrowDispatches.where((d) {
        try {
          final dateOut = DateTime.parse(d.dateOut);
          return dateOut.isAfter(fromStart) && dateOut.isBefore(toEnd);
        } catch (_) { return false; }
      }).toList();
      final toExport = inRange.where((d) {
        if (widget.exportOut && d.dateIn == null) return true;
        if (widget.exportReturned && d.dateIn != null) return true;
        return false;
      }).toList();
      final Map<int, List<DispatchItem>> itemsMap = {};
      for (final d in toExport) {
        if (d.id != null) itemsMap[d.id!] = await DBHelper.instance.getDispatchItems(d.id!);
      }
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final now = DateTime.now();
      final dateRangeStr = '${_fmtShort(_fromDate!.toIso8601String())} – ${_fmtShort(_toDate!.toIso8601String())}';
      final sheet1Label = widget.exportOut && widget.exportReturned
          ? 'Borrow Records'
          : widget.exportOut ? 'Active Borrows' : 'Returned Borrows';
      final sheet1 = excel[sheet1Label];
      _writeHeaders(sheet1, [
        'Dispatch No.', 'Borrower Name', 'Borrower ID',
        'Instrument', 'Instrument Code', 'Date Out', 'Date In',
        'Processed By', 'Contact', 'Purpose', 'Condition',
      ]);
      int totalRows = 0;
      for (final d in toExport) {
        final items = itemsMap[d.id] ?? [];
        final borrower = d.studentName ?? d.testEngineer;
        final borrowerId = d.studentId ?? '—';
        if (items.isEmpty) {
          sheet1.appendRow([
            TextCellValue(d.dispatchNo), TextCellValue(borrower),
            TextCellValue(borrowerId), TextCellValue('—'), TextCellValue('—'),
            TextCellValue(_fmtLong(d.dateOut)), TextCellValue(_fmtLong(d.dateIn)),
            TextCellValue(d.processedByName ?? '—'),
            TextCellValue(d.borrowerContact ?? '—'),
            TextCellValue(d.borrowerPurpose ?? '—'), TextCellValue('—'),
          ]);
          totalRows++;
        } else {
          for (final item in items) {
            final condition = (d.dateIn != null && item.returnCondition != null && item.returnCondition!.isNotEmpty)
                ? item.returnCondition! : item.currentCondition;
            sheet1.appendRow([
              TextCellValue(d.dispatchNo), TextCellValue(borrower),
              TextCellValue(borrowerId), TextCellValue(item.instrumentName),
              TextCellValue(item.instrumentCode),
              TextCellValue(_fmtLong(d.dateOut)), TextCellValue(_fmtLong(d.dateIn)),
              TextCellValue(d.processedByName ?? '—'),
              TextCellValue(d.borrowerContact ?? '—'),
              TextCellValue(d.borrowerPurpose ?? '—'), TextCellValue(condition),
            ]);
            totalRows++;
            if (d.dateIn == null) {
              final rowIdx = sheet1.maxRows - 1;
              for (int c = 0; c < 11; c++) {
                sheet1.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx))
                    .cellStyle = CellStyle(fontColorHex: ExcelColor.fromHexString('#FF8C00'));
              }
            }
          }
        }
      }
      for (int i = 0; i < 11; i++) sheet1.setColumnWidth(i, i == 3 ? 28 : i == 1 ? 22 : 18);
      final summary = excel['Summary'];
      final outCount = toExport.where((d) => d.dateIn == null).length;
      final retCount = toExport.where((d) => d.dateIn != null).length;
      final filterLabel = widget.exportOut && widget.exportReturned ? 'All (Active + Returned)'
          : widget.exportOut ? 'Active only' : 'Returned only';
      for (final r in [
        ['AMTEC Tool Tracker — Borrow Records Export', ''],
        ['', ''],
        ['Export Date', DateFormat('MMMM dd, yyyy  hh:mm a').format(now)],
        ['Date Range', dateRangeStr],
        ['Filter', filterLabel],
        ['', ''],
        ['Total Borrows', '${toExport.length}'],
        ['Total Rows', '$totalRows'],
        ['Currently Out', '$outCount'],
        ['Returned', '$retCount'],
      ]) { summary.appendRow(r.map((v) => TextCellValue(v)).toList()); }
      summary.setColumnWidth(0, 30); summary.setColumnWidth(1, 22);
      final dirPath = await _getDownloadsPath();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filePath = '$dirPath/AMTEC_BorrowRecords_$timestamp.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');
      await File(filePath).writeAsBytes(bytes);
      setState(() => _loading = false);
      if (mounted) _showSuccess(filePath, totalRows, 2);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportDispatch() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select both From and To dates'),
          backgroundColor: Colors.orange));
      return;
    }

    setState(() => _loading = true);
    try {
      final fromStart =
          DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final toEnd = DateTime(
          _toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);

      final allDispatches =
          await DBHelper.instance.getAllDispatches();

      // Apply staff-only + date range filter
      final staffDispatches = allDispatches.where((d) => !d.isStudent).toList();
      final inRange = staffDispatches.where((d) {
        try {
          final dateOut = DateTime.parse(d.dateOut);
          return dateOut.isAfter(fromStart) && dateOut.isBefore(toEnd);
        } catch (_) {
          return false;
        }
      }).toList();

      // Apply out/returned filter
      final toExport = inRange.where((d) {
        if (widget.exportOut && d.dateIn == null) return true;
        if (widget.exportReturned && d.dateIn != null) return true;
        return false;
      }).toList();

      final Map<int, List<DispatchItem>> itemsMap = {};
      for (final d in toExport) {
        if (d.id != null) {
          itemsMap[d.id!] = await DBHelper.instance.getDispatchItems(d.id!);
        }
      }

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final now = DateTime.now();
      final dateRangeStr =
          '${_fmtShort(_fromDate!.toIso8601String())} – ${_fmtShort(_toDate!.toIso8601String())}';

// ── Sheet 1: Dispatch Records (one row per instrument) ───────────────
      final sheet1Label = widget.exportOut && widget.exportReturned
          ? 'Dispatch Records'
          : widget.exportOut
              ? 'Active Dispatches'
              : 'Returned Dispatches';

      final sheet1 = excel[sheet1Label];
      _writeHeaders(sheet1, [
        'Dispatch No.',
        'Instrument',
        'Instrument Code',
        'Test Engineer',
        'Date Out',
        'Date In',
        'Processed By',
        'Current Condition',
        'Remarks',
      ]);

      int totalRows = 0;
      for (final d in toExport) {
        final items = itemsMap[d.id] ?? [];
        if (items.isEmpty) {
          // Dispatch with no items — still emit one row so it's not lost
          sheet1.appendRow([
            TextCellValue(d.dispatchNo),
            TextCellValue('—'),
            TextCellValue('—'),
            TextCellValue(d.testEngineer),
            TextCellValue(_fmtLong(d.dateOut)),
            TextCellValue(_fmtLong(d.dateIn)),
            TextCellValue(d.processedByName ?? '—'),
            TextCellValue('—'),
            TextCellValue(d.remarks ?? ''),
          ]);
          totalRows++;
          if (d.dateIn == null) {
            final rowIdx = sheet1.maxRows - 1;
            for (int c = 0; c < 9; c++) {
              final cell = sheet1.cell(
                  CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx));
              cell.cellStyle =
                  CellStyle(fontColorHex: ExcelColor.fromHexString('#FF8C00'));
            }
          }
        } else {
          for (final item in items) {
            // Current condition: prefer return condition if returned, else dispatch condition
            final condition = (d.dateIn != null && item.returnCondition != null && item.returnCondition!.isNotEmpty)
                ? item.returnCondition!
                : item.currentCondition;
            sheet1.appendRow([
              TextCellValue(d.dispatchNo),
              TextCellValue(item.instrumentName),
              TextCellValue(item.instrumentCode),
              TextCellValue(d.testEngineer),
              TextCellValue(_fmtLong(d.dateOut)),
              TextCellValue(_fmtLong(d.dateIn)),
              TextCellValue(d.processedByName ?? '—'),
              TextCellValue(condition),
              TextCellValue(d.remarks ?? ''),
            ]);
            totalRows++;
            if (d.dateIn == null) {
              final rowIdx = sheet1.maxRows - 1;
              for (int c = 0; c < 9; c++) {
                final cell = sheet1.cell(
                    CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx));
                cell.cellStyle =
                    CellStyle(fontColorHex: ExcelColor.fromHexString('#FF8C00'));
              }
            }
          }
        }
      }
      sheet1.setColumnWidth(0, 20);
      sheet1.setColumnWidth(1, 28);
      sheet1.setColumnWidth(2, 18);
      sheet1.setColumnWidth(3, 22);
      sheet1.setColumnWidth(4, 24);
      sheet1.setColumnWidth(5, 24);
      sheet1.setColumnWidth(6, 18);
      sheet1.setColumnWidth(7, 20);
      sheet1.setColumnWidth(8, 22);

      // ── Summary ──────────────────────────────────────────────────────────
      final summary = excel['Summary'];
      final outCount = toExport.where((d) => d.dateIn == null).length;
      final retCount = toExport.where((d) => d.dateIn != null).length;
      final filterLabel = widget.exportOut && widget.exportReturned
          ? 'All (Out + Returned)'
          : widget.exportOut
              ? 'Out only'
              : 'Returned only';
      final summaryRows = [
        ['AMTEC Tool Tracker — Dispatch Records Export', ''],
        ['', ''],
        ['Export Date', DateFormat('MMMM dd, yyyy  hh:mm a').format(now)],
        ['Date Range', dateRangeStr],
        ['Filter', filterLabel],
        ['', ''],
        ['Total Dispatches', '${toExport.length}'],
        ['Total Instrument Rows', '$totalRows'],
        ['Currently Out', '$outCount'],
        ['Returned', '$retCount'],
      ];
      for (final r in summaryRows) {
        summary.appendRow(r.map((v) => TextCellValue(v)).toList());
      }
      summary.setColumnWidth(0, 30);
      summary.setColumnWidth(1, 22);

      final dirPath = await _getDownloadsPath();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filePath = '$dirPath/AMTEC_Dispatches_$timestamp.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');
      await File(filePath).writeAsBytes(bytes);

      setState(() => _loading = false);
      if (mounted) _showSuccess(filePath, totalRows, 2);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportConditionHistory() async {
    setState(() => _loading = true);
    try {
      final allHistory = await DBHelper.instance.getConditionHistory();
      final history = _selectedCodes.isEmpty
          ? allHistory
          : allHistory
              .where((r) => _selectedCodes.contains(r['instrument_code']))
              .toList();

      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final now = DateTime.now();

      final sheet1 = excel['Condition History'];
      _writeHeaders(sheet1, [
        'Date',
        'Instrument Code',
        'Instrument Name',
        'Dispatch No.',
        'Condition at Dispatch',
        'Return Condition',
        'Changed By',
      ]);
      for (final row in history) {
        sheet1.appendRow([
          TextCellValue(row['date'] ?? ''),
          TextCellValue(row['instrument_code'] ?? ''),
          TextCellValue(row['instrument_name'] ?? ''),
          TextCellValue(row['dispatch_no'] ?? ''),
          TextCellValue(row['current_condition'] ?? ''),
          TextCellValue(row['return_condition'] ?? ''),
          TextCellValue(row['changed_by'] ?? ''),
        ]);
      }
      sheet1.setColumnWidth(0, 24);
      sheet1.setColumnWidth(1, 18);
      sheet1.setColumnWidth(2, 28);
      sheet1.setColumnWidth(3, 18);

      // Summary
      final summary = excel['Summary'];
      final repairCount = history
          .where((r) =>
              r['return_condition'] == 'For Repair' ||
              r['current_condition'] == 'For Repair')
          .length;
      final condemnCount = history
          .where((r) =>
              r['return_condition'] == 'Condemning' ||
              r['current_condition'] == 'Condemning')
          .length;
      final summaryRows = [
        ['AMTEC Tool Tracker — Condition History Export', ''],
        ['', ''],
        ['Export Date', DateFormat('MMMM dd, yyyy  hh:mm a').format(now)],
        ['', ''],
        ['Total Records', '${history.length}'],
        ['For Repair', '$repairCount'],
        ['Condemning', '$condemnCount'],
      ];
      for (final r in summaryRows) {
        summary.appendRow(r.map((v) => TextCellValue(v)).toList());
      }
      summary.setColumnWidth(0, 30);
      summary.setColumnWidth(1, 22);

      final dirPath = await _getDownloadsPath();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filePath = '$dirPath/AMTEC_ConditionHistory_$timestamp.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');
      await File(filePath).writeAsBytes(bytes);

      setState(() => _loading = false);
      if (mounted) _showSuccess(filePath, history.length, 2);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _runMultiExport() async {
    setState(() => _loading = true);
    try {
      final allInstruments = await DBHelper.instance.getAllInstruments();
      final now = DateTime.now();
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      int totalSheets = 0;

      for (final type in widget.multiExportTypes ?? []) {
        switch (type) {
          case ExportType.dispatch:
            // Dispatch needs date range — skip if not set, just add a note sheet
            final sheet = excel['Dispatch Records'];
            _writeHeaders(sheet, ['Note']);
            sheet.appendRow([TextCellValue('Use the Dispatch export option with date filters for dispatch records.')]);
            totalSheets++;
          case ExportType.conditionHistory:
            final allHistory = await DBHelper.instance.getConditionHistory();
            final history = _selectedCodes.isEmpty
                ? allHistory
                : allHistory.where((r) =>
                    _selectedCodes.contains(r['instrument_code'])).toList();
            final sheet = excel['Condition History'];
            _writeHeaders(sheet, ['Date', 'Instrument Code', 'Instrument Name', 'Dispatch No.', 'Condition at Dispatch', 'Return Condition', 'Changed By']);
            for (final row in history) {
              sheet.appendRow([
                TextCellValue(row['date'] ?? ''),
                TextCellValue(row['instrument_code'] ?? ''),
                TextCellValue(row['instrument_name'] ?? ''),
                TextCellValue(row['dispatch_no'] ?? ''),
                TextCellValue(row['current_condition'] ?? ''),
                TextCellValue(row['return_condition'] ?? ''),
                TextCellValue(row['changed_by'] ?? ''),
              ]);
            }
            sheet.setColumnWidth(0, 24); sheet.setColumnWidth(1, 18);
            sheet.setColumnWidth(2, 28); sheet.setColumnWidth(3, 18);
            totalSheets++;
          case ExportType.upcoming:
            final list = allInstruments.where((i) => i.isUpcoming(withinDays: 30)).toList();
            final sheet = excel['Upcoming Schedule'];
            _writeHeaders(sheet, ['Instrument Code', 'Instrument Name', 'Serial Number', 'Condition', 'Status', 'Location', 'Scheduled Repair', 'Scheduled Condemn', 'Notes']);
            for (final i in list) {
              sheet.appendRow([TextCellValue(i.instrumentCode), TextCellValue(i.instrumentName), TextCellValue(i.serialNumber ?? '—'), TextCellValue(i.currentCondition), TextCellValue(i.status), TextCellValue(i.location ?? '—'), TextCellValue(i.scheduledRepairDate ?? '—'), TextCellValue(i.scheduledCondemnDate ?? '—'), TextCellValue(i.notes ?? '')]);
            }
            sheet.setColumnWidth(0, 16); sheet.setColumnWidth(1, 26); sheet.setColumnWidth(2, 18);
            totalSheets++;
          case ExportType.overdue:
            final overdueNow = DateTime.now();
            final list = allInstruments.where((i) {
              if (i.scheduledRepairDate != null) { try { if (DateTime.parse(i.scheduledRepairDate!).isBefore(overdueNow)) return true; } catch (_) {} }
              if (i.scheduledCondemnDate != null) { try { if (DateTime.parse(i.scheduledCondemnDate!).isBefore(overdueNow)) return true; } catch (_) {} }
              return i.isOverdue;
            }).toList();
            final sheet = excel['Overdue Instruments'];
            _writeHeaders(sheet, ['Instrument Code', 'Instrument Name', 'Serial Number', 'Condition', 'Status', 'Location', 'Days Out / Past Due', 'Scheduled Repair', 'Scheduled Condemn']);
            for (final i in list) {
              sheet.appendRow([TextCellValue(i.instrumentCode), TextCellValue(i.instrumentName), TextCellValue(i.serialNumber ?? '—'), TextCellValue(i.currentCondition), TextCellValue(i.status), TextCellValue(i.location ?? '—'), TextCellValue(i.isOverdue ? '${i.daysOut} days out' : '—'), TextCellValue(i.scheduledRepairDate ?? '—'), TextCellValue(i.scheduledCondemnDate ?? '—')]);
            }
            sheet.setColumnWidth(0, 16); sheet.setColumnWidth(1, 26);
            totalSheets++;
          case ExportType.forRepair:
            final list = allInstruments.where((i) => i.currentCondition == 'For Repair').toList();
            final sheet = excel['For Repair'];
            _writeHeaders(sheet, ['Instrument Code', 'Instrument Name', 'Serial Number', 'Condition', 'Status', 'Location', 'Scheduled Repair Date', 'Notes']);
            for (final i in list) {
              sheet.appendRow([TextCellValue(i.instrumentCode), TextCellValue(i.instrumentName), TextCellValue(i.serialNumber ?? '—'), TextCellValue(i.currentCondition), TextCellValue(i.status), TextCellValue(i.location ?? '—'), TextCellValue(i.scheduledRepairDate ?? '—'), TextCellValue(i.notes ?? '')]);
            }
            sheet.setColumnWidth(0, 16); sheet.setColumnWidth(1, 26);
            totalSheets++;
          case ExportType.forCondemn:
            final list = allInstruments.where((i) => i.currentCondition == 'Condemning').toList();
            final sheet = excel['For Condemning'];
            _writeHeaders(sheet, ['Instrument Code', 'Instrument Name', 'Serial Number', 'Condition', 'Status', 'Location', 'Scheduled Condemn Date', 'Notes']);
            for (final i in list) {
              sheet.appendRow([TextCellValue(i.instrumentCode), TextCellValue(i.instrumentName), TextCellValue(i.serialNumber ?? '—'), TextCellValue(i.currentCondition), TextCellValue(i.status), TextCellValue(i.location ?? '—'), TextCellValue(i.scheduledCondemnDate ?? '—'), TextCellValue(i.notes ?? '')]);
            }
            sheet.setColumnWidth(0, 16); sheet.setColumnWidth(1, 26);
            totalSheets++;
          case ExportType.instrumentsOut:
            final list = allInstruments.where((i) => i.status == 'In Use').toList();
            final sheet = excel['Instruments Out'];
            _writeHeaders(sheet, ['Instrument Code', 'Instrument Name', 'Serial Number', 'Condition', 'Status', 'Location', 'Last Touch Date', 'Last Touch By', 'Days Out']);
            for (final i in list) {
              sheet.appendRow([TextCellValue(i.instrumentCode), TextCellValue(i.instrumentName), TextCellValue(i.serialNumber ?? '—'), TextCellValue(i.currentCondition), TextCellValue(i.status), TextCellValue(i.location ?? '—'), TextCellValue(i.lastTouchDate ?? '—'), TextCellValue(i.lastTouchBy ?? '—'), TextCellValue('${i.daysOut}')]);
            }
            sheet.setColumnWidth(0, 16); sheet.setColumnWidth(1, 26);
            totalSheets++;
        }
      }

      // Summary sheet
      final summary = excel['Summary'];
      summary.appendRow([TextCellValue('AMTEC Tool Tracker — Multi-Export'), TextCellValue('')]);
      summary.appendRow([TextCellValue(''), TextCellValue('')]);
      summary.appendRow([TextCellValue('Export Date'), TextCellValue(DateFormat('MMMM dd, yyyy  hh:mm a').format(now))]);
      summary.appendRow([TextCellValue('Sheets Exported'), TextCellValue('$totalSheets')]);
      summary.setColumnWidth(0, 30); summary.setColumnWidth(1, 28);

      final dirPath = await _getDownloadsPath();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filePath = '$dirPath/AMTEC_MultiExport_$timestamp.xlsx';
      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');
      await File(filePath).writeAsBytes(bytes);

      setState(() => _loading = false);
      if (mounted) _showSuccess(filePath, totalSheets, totalSheets + 1);
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red));
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
        backgroundColorHex: ExcelColor.fromHexString('#1E3A5F'),
        fontColorHex: ExcelColor.fromHexString('#F5A623'),
      );
    }
  }

  void _showSuccess(String path, int count, int sheets) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.check_circle, color: Colors.green, size: 22),
          SizedBox(width: 8),
          Text('Export Complete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count records exported · $sheets sheets',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            Text(path.split('/').last,
                style: const TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(path, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = (widget.multiExportTypes?.length ?? 0) > 1;
    final isDispatch = !isMulti && (widget.exportType == ExportType.dispatch || widget.exportType == ExportType.borrow);
    final isBorrow = !isMulti && widget.exportType == ExportType.borrow;
    final filterLabel = widget.exportOut && widget.exportReturned
        ? 'All records'
        : widget.exportOut
            ? 'Currently out only'
            : 'Returned only';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        title: Text(
          widget.exportType == ExportType.borrow
              ? 'Export Borrow Records'
              : isDispatch
              ? 'Export Dispatch Records'
              : widget.exportType == ExportType.upcoming
                  ? 'Export Upcoming Schedule'
                  : widget.exportType == ExportType.overdue
                      ? 'Export Overdue Instruments'
                      : widget.exportType == ExportType.forRepair
                          ? 'Export Instruments For Repair'
                          : widget.exportType == ExportType.forCondemn
                              ? 'Export Instruments For Condemning'
                              : widget.exportType == ExportType.instrumentsOut
                                  ? 'Export Instruments Currently Out'
                                  : 'Export Condition History',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
            if (isMulti) ...[
              const Text('SELECTED EXPORT TYPES',
                  style: TextStyle(color: Color(0xFFF5A623), fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...(widget.multiExportTypes ?? []).map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 8),
                  Text(t.name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              )),
              const SizedBox(height: 24),
              const Text('Each selected type will be exported as a separate sheet in one Excel file.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _runMultiExport,
                  icon: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT ALL TO EXCEL',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ] else if (isDispatch) ...[
              // Filter summary badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFF5A623).withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.filter_list,
                      color: Color(0xFFF5A623), size: 16),
                  const SizedBox(width: 8),
                  Text('Exporting: $filterLabel',
                      style: const TextStyle(
                          color: Color(0xFFF5A623),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 20),
              const Text('DATE RANGE',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _dateTile('From', _fromDate, () => _pickDate(isFrom: true)),
              const SizedBox(height: 10),
              _dateTile('To', _toDate, () => _pickDate(isFrom: false)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : (isBorrow ? _exportBorrow : _exportDispatch),
                  icon: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT TO EXCEL',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ] else ...[
              // ── Condition History: toggle between date range and instrument select ──
              // Toggle row
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _useByDate = true),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _useByDate
                            ? const Color(0xFFF5A623).withValues(alpha: 0.15)
                            : const Color(0xFF1A3A5C),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _useByDate
                                ? const Color(0xFFF5A623)
                                : const Color(0xFF1E3A5F)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.date_range,
                            color: _useByDate
                                ? const Color(0xFFF5A623)
                                : Colors.white38,
                            size: 16),
                        const SizedBox(width: 6),
                        Text('By Date Range',
                            style: TextStyle(
                                color: _useByDate
                                    ? const Color(0xFFF5A623)
                                    : Colors.white38,
                                fontSize: 12,
                                fontWeight: _useByDate
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _useByDate = false),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_useByDate
                            ? const Color(0xFFF5A623).withValues(alpha: 0.15)
                            : const Color(0xFF1A3A5C),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: !_useByDate
                                ? const Color(0xFFF5A623)
                                : const Color(0xFF1E3A5F)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.checklist,
                            color: !_useByDate
                                ? const Color(0xFFF5A623)
                                : Colors.white38,
                            size: 16),
                        const SizedBox(width: 6),
                        Text('Select Instruments',
                            style: TextStyle(
                                color: !_useByDate
                                    ? const Color(0xFFF5A623)
                                    : Colors.white38,
                                fontSize: 12,
                                fontWeight: !_useByDate
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              if (_useByDate) ...[ 
                // ── By date range ──────────────────────────────────────
                const Text('DATE RANGE',
                    style: TextStyle(color: Color(0xFFF5A623),
                        fontSize: 10, letterSpacing: 3,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _dateTile('From', _fromDate, () => _pickDate(isFrom: true)),
                const SizedBox(height: 10),
                _dateTile('To', _toDate, () => _pickDate(isFrom: false)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _exportConditionHistory,
                    icon: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.download, color: Colors.black),
                    label: const Text('EXPORT TO EXCEL',
                        style: TextStyle(color: Colors.black,
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5A623),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ] else ...[ 
                // ── Select instruments individually ────────────────────
                Row(children: [
                  const Expanded(
                    child: Text('FILTER BY INSTRUMENT',
                        style: TextStyle(color: Color(0xFFF5A623),
                            fontSize: 10, letterSpacing: 3,
                            fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => setState(() =>
                        _selectedCodes = List.from(_allInstrumentCodes)),
                    child: const Text('All',
                        style: TextStyle(color: Color(0xFFF5A623), fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedCodes = []),
                    child: const Text('None',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search instrument name or code...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white38, size: 18),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xFF1E3A5F))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xFFF5A623))),
                    filled: true,
                    fillColor: const Color(0xFF1A3A5C),
                  ),
                  onChanged: (v) => setState(
                      () => _codeSearch = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 280,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A5C),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: _allInstrumentCodes.isEmpty
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFF5A623), strokeWidth: 2))
                      : ListView(
                          padding: EdgeInsets.zero,
                          children: _allInstrumentCodes
                              .where((c) {
                                if (_codeSearch.isEmpty) return true;
                                final name = (_codeToName[c] ?? '').toLowerCase();
                                return name.contains(_codeSearch) ||
                                    c.toLowerCase().contains(_codeSearch);
                              })
                              .map((code) {
                            final selected = _selectedCodes.contains(code);
                            final name = _codeToName[code] ?? code;
                            return CheckboxListTile(
                              dense: true,
                              value: selected,
                              activeColor: const Color(0xFFF5A623),
                              checkColor: Colors.black,
                              title: Text(name,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                              subtitle: Text(code,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10)),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selectedCodes.add(code);
                                } else {
                                  _selectedCodes.remove(code);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                    '${_selectedCodes.length} of '
                    '${_allInstrumentCodes.length} selected',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: (_loading || _selectedCodes.isEmpty)
                        ? null
                        : _exportConditionHistory,
                  icon: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.download, color: Colors.black),
                  label: const Text('EXPORT CONDITION HISTORY',
                      style: TextStyle(color: Colors.black,
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
            ],
            ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? now.subtract(const Duration(days: 30)))
          : (_toDate ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
                primary: Color(0xFFF5A623),
                onPrimary: Colors.black,
                surface: Color(0xFF1A3A5C))),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    final isSet = date != null;
    final display = isSet
        ? '${date.day}/${date.month}/${date.year}'
        : 'Tap to set $label date';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSet
              ? const Color(0xFFF5A623).withValues(alpha: 0.08)
              : const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSet
                  ? const Color(0xFFF5A623)
                  : const Color(0xFF1E3A5F)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today,
              color: isSet
                  ? const Color(0xFFF5A623)
                  : Colors.white38,
              size: 18),
          const SizedBox(width: 12),
          Expanded(
              child: Text(display,
                  style: TextStyle(
                      color: isSet
                          ? const Color(0xFFF5A623)
                          : Colors.white38,
                      fontSize: 14,
                      fontWeight: isSet
                          ? FontWeight.bold
                          : FontWeight.normal))),
          if (isSet)
            GestureDetector(
              onTap: () => setState(() {
                if (label == 'From') _fromDate = null;
                else _toDate = null;
              }),
              child: const Icon(Icons.close, color: Colors.white38, size: 18),
            ),
        ]),
      ),
    );
  }
}