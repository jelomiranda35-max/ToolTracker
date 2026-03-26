// instruments_tab.dart — Build 15
//  ✅ Fix 1: Scheduled dates now preserved through sync (sync_service must use upsertInstrumentFromServer)
//  ✅ Fix 2: Date picker prompt added in return flow (handled in return_scanner_screen.dart)
//  ✅ Fix 3: Excel saved to /storage/emulated/0/Download/ (Downloads folder)
//  ✅ Fix 5: Filter chips (Repair/Condemned/Overdue/Upcoming) show ONLY matched units — no group siblings
//  ✅ Fix 6: Upcoming tab shows For Repair / Condemning instruments even without a scheduled date

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../models/instrument.dart';
import 'dispatch_export_screen.dart';

enum InstrumentFilter { all, overdue, forRepair, condemned, upcoming }
enum InstrumentSort { alphabetical, mostInUse, mostOverdue, conditionPriority }

// ═════════════════════════════════════════════════════════════════════════════
// STANDALONE HELPER
// ═════════════════════════════════════════════════════════════════════════════

Future<void> checkOverdueAlerts(
  BuildContext context, {
  VoidCallback? onViewOverdue,
  VoidCallback? onViewUpcoming,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final threshold = prefs.getInt('overdue_days') ?? 7;
  Instrument.setOverdueThreshold(threshold);

  if (!context.mounted) return;
  final instruments = await DBHelper.instance.getAllInstruments();

  // Notifications are shown in the notification bell — no bottom snackbars
}

// ══════════════════════════════════════════════════════════════════════════════
// INSTRUMENTS TAB
// ══════════════════════════════════════════════════════════════════════════════

class InstrumentsTab extends StatefulWidget {
  final VoidCallback onRefresh;
  final bool isActive; // true when this tab is currently selected
  const InstrumentsTab({super.key, required this.onRefresh, this.isActive = false});

  @override
  State<InstrumentsTab> createState() => InstrumentsTabState();
}

class InstrumentsTabState extends State<InstrumentsTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _subTabController;
  List<Instrument> _instruments = [];
  static const int _upcomingWindowDays = 30;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadThreshold();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subTabController.dispose();
    super.dispose();
  }

  /// Reload instruments when app resumes from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Called by home_screen when this tab becomes active
  void reload() => _load();

  @override
  void didUpdateWidget(InstrumentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload from DB every time this tab becomes the active tab
    if (!oldWidget.isActive && widget.isActive) {
      _load();
    }
  }

  Future<void> _loadThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    Instrument.setOverdueThreshold(prefs.getInt('overdue_days') ?? 7);
  }

  Future<void> _load() async {
    final instruments = await DBHelper.instance.getAllInstruments();
    if (!mounted) return;
    setState(() => _instruments = instruments);
  }

  void activateOverdueFilter() => _subTabController.animateTo(0);
  void activateUpcomingFilter() => _subTabController.animateTo(1);

  int get overdueCount => _instruments.where((i) => i.isOverdue).length;
  int get upcomingCount =>
      _instruments.where((i) =>
          i.isUpcoming(withinDays: _upcomingWindowDays) || i.calibrationDueSoon || i.isCalibrationOverdue
      ).length;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Builder(builder: (context) {
          final tc = context.watch<ThemeNotifier>().colors;
          return Container(
          color: tc.surfaceVariant,
          child: TabBar(
            controller: _subTabController,
            indicatorColor: tc.accent,
            indicatorWeight: 2,
            labelColor: tc.accent,
            unselectedLabelColor: tc.textHint,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: [
              const Tab(text: 'All Instruments'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Upcoming'),
                    if (upcomingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Text('$upcomingCount',
                            style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
        }),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _InstrumentListSubTab(instruments: _instruments, onReload: _load),
              _UpcomingSubTab(instruments: _instruments, onReload: _load),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUB-TAB A — ALL INSTRUMENTS
// ══════════════════════════════════════════════════════════════════════════════

class _InstrumentListSubTab extends StatefulWidget {
  final List<Instrument> instruments;
  final VoidCallback onReload;
  const _InstrumentListSubTab({required this.instruments, required this.onReload});

  @override
  State<_InstrumentListSubTab> createState() => _InstrumentListSubTabState();
}

class _InstrumentListSubTabState extends State<_InstrumentListSubTab> {
  List<Instrument> _filtered = [];
  final _searchController = TextEditingController();
  final Set<String> _expandedGroups = {};

  InstrumentFilter _activeFilter = InstrumentFilter.all;
  InstrumentSort _activeSort = InstrumentSort.alphabetical;

  static const int _upcomingWindowDays = 30;

  @override
  void initState() {
    super.initState();
    _applyFilter();
  }

  @override
  void didUpdateWidget(_InstrumentListSubTab old) {
    super.didUpdateWidget(old);
    if (old.instruments != widget.instruments) _applyFilter();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _overdueCount => widget.instruments.where((i) => i.isOverdue).length;
  int get _repairCount =>
      widget.instruments.where((i) => i.currentCondition == 'For Repair').length;
  int get _condemnCount =>
      widget.instruments.where((i) => i.currentCondition == 'Condemning').length;
  int get _upcomingCount =>
      widget.instruments.where((i) =>
          i.isUpcoming(withinDays: _upcomingWindowDays) || i.calibrationDueSoon || i.isCalibrationOverdue
      ).length;

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    List<Instrument> base;
    switch (_activeFilter) {
      case InstrumentFilter.all:
        base = List.from(widget.instruments);
        break;
      case InstrumentFilter.overdue:
        base = widget.instruments.where((i) => i.isOverdue).toList();
        break;
      case InstrumentFilter.forRepair:
        base = widget.instruments.where((i) => i.currentCondition == 'For Repair').toList();
        break;
      case InstrumentFilter.condemned:
        base = widget.instruments.where((i) => i.currentCondition == 'Condemning').toList();
        break;
      case InstrumentFilter.upcoming:
        base = widget.instruments
            .where((i) => i.isUpcoming(withinDays: _upcomingWindowDays))
            .toList()
          ..sort((a, b) => _minDaysAway(a).compareTo(_minDaysAway(b)));
        break;
    }
    if (q.isNotEmpty) {
      base = base
          .where((i) =>
              i.instrumentName.toLowerCase().contains(q) ||
              i.instrumentCode.toLowerCase().contains(q))
          .toList();
    }
    if (_activeFilter != InstrumentFilter.upcoming) _applySortTo(base);
    setState(() => _filtered = base);
  }

  void _applySortTo(List<Instrument> list) {
    switch (_activeSort) {
      case InstrumentSort.alphabetical:
        list.sort((a, b) => a.instrumentName.compareTo(b.instrumentName));
        break;
      case InstrumentSort.mostInUse:
        list.sort((a, b) {
          final aS = a.status == 'In Use' ? 1 : 0;
          final bS = b.status == 'In Use' ? 1 : 0;
          if (bS != aS) return bS.compareTo(aS);
          return a.instrumentName.compareTo(b.instrumentName);
        });
        break;
      case InstrumentSort.mostOverdue:
        list.sort((a, b) => b.daysOut.compareTo(a.daysOut));
        break;
      case InstrumentSort.conditionPriority:
        list.sort((a, b) {
          const p = {'Condemning': 0, 'For Repair': 1, 'Functioning': 2};
          final ap = p[a.currentCondition] ?? 3;
          final bp = p[b.currentCondition] ?? 3;
          if (ap != bp) return ap.compareTo(bp);
          return a.instrumentName.compareTo(b.instrumentName);
        });
        break;
    }
  }

  int _minDaysAway(Instrument i) {
    final r = i.daysUntilRepair;
    final c = i.daysUntilCondemn;
    if (r == null && c == null) return 9998; // no-date instruments sort to bottom
    if (r == null) return c!;
    if (c == null) return r;
    return r < c ? r : c;
  }

  void _setFilter(InstrumentFilter f) {
    setState(() => _activeFilter = f);
    _applyFilter();
  }

  void _setSort(InstrumentSort s) {
    setState(() => _activeSort = s);
    _applyFilter();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'Available': return Colors.green;
      case 'In Use': return Colors.orange;
      default: return Colors.red;
    }
  }

  Color _conditionColor(String? c) {
    switch (c) {
      case 'Functioning': return Colors.green;
      case 'For Repair': return Colors.orange;
      case 'Condemning': return Colors.red;
      case 'For Calibration': return Colors.blue;
      default: return Colors.white38;
    }
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return 'Never';
    try {
      final d = DateTime.parse(s);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  void _openEditSheet(Instrument unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) =>
          _InstrumentEditSheet(instrument: unit, onSaved: widget.onReload),
    );
  }

  void _showUnitHistory(Instrument unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _UnitHistorySheet(
          unit: unit, onEdit: () => _openEditSheet(unit)),
    );
  }

  void _showStaffExportMenu(BuildContext context, AppColors colors) {
    bool expCondHistory = false;
    bool expUpcoming = false;
    bool expOverdue = false;
    bool expOut = false;
    // Condition history sub-options
    bool condByDate = true;
    DateTime condFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    List<Map<String, String>> condAllInstruments = []; // {code, name}
    List<String> condSelectedCodes = [];
    String condSearch = '';
    // Load instruments with names
    DBHelper.instance.getAllInstruments().then((list) {
      list.sort((a, b) => a.instrumentName.compareTo(b.instrumentName));
      condAllInstruments = list.map((i) => {'code': i.instrumentCode, 'name': i.instrumentName}).toList();
      condSelectedCodes = list.map((i) => i.instrumentCode).toList();
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
              const Text('EXPORT INSTRUMENTS',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 10,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Select the data to include, then export.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 16),
              _staffExportCheckbox('Instrument Condition History', Icons.history,
                  Colors.blue, expCondHistory,
                  (v) => setModalState(() => expCondHistory = v!)),
              if (expCondHistory) ...[
                Container(
                  margin: const EdgeInsets.only(left: 12, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FILTER BY',
                          style: TextStyle(color: Colors.blue, fontSize: 9,
                              letterSpacing: 2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(children: [
                        GestureDetector(
                          onTap: () => setModalState(() => condByDate = true),
                          child: Row(children: [
                            Icon(condByDate ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: condByDate ? const Color(0xFFF5A623) : Colors.white38, size: 16),
                            const SizedBox(width: 4),
                            Text('By Date Range',
                                style: TextStyle(
                                    color: condByDate ? Colors.white : Colors.white38,
                                    fontSize: 11)),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => setModalState(() => condByDate = false),
                          child: Row(children: [
                            Icon(!condByDate ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: !condByDate ? const Color(0xFFF5A623) : Colors.white38, size: 16),
                            const SizedBox(width: 4),
                            Text('Select Instruments',
                                style: TextStyle(
                                    color: !condByDate ? Colors.white : Colors.white38,
                                    fontSize: 11)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (condByDate) ...[
                        Row(children: [
                          const Text('From:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: condFromDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                          primary: Color(0xFFF5A623),
                                          surface: Color(0xFF1A3A5C))),
                                  child: child!,
                                ),
                              );
                              if (picked != null) setModalState(() => condFromDate = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D1B2A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('${condFromDate.day}/${condFromDate.month}/${condFromDate.year}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit_calendar, color: Color(0xFFF5A623), size: 12),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('To: Today', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                      ] else ...[
                        TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search instrument code...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 16),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: Colors.blue.withValues(alpha: 0.4))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFF5A623))),
                            filled: true,
                            fillColor: const Color(0xFF0D1B2A),
                          ),
                          onChanged: (v) => setModalState(() => condSearch = v.toLowerCase()),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          TextButton(
                            onPressed: () => setModalState(() => condSelectedCodes = condAllInstruments.map((i) => i['code']!).toList()),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                            child: const Text('All', style: TextStyle(color: Color(0xFFF5A623), fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => setModalState(() => condSelectedCodes = []),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                            child: const Text('None', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                          const Spacer(),
                          Text('${condSelectedCodes.length} selected',
                              style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        ]),
                        Container(
                          height: 150,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D1B2A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                          ),
                          child: condAllInstruments.isEmpty
                              ? const Center(child: CircularProgressIndicator(
                                  color: Color(0xFFF5A623), strokeWidth: 2))
                              : ListView(
                                  padding: EdgeInsets.zero,
                                  children: condAllInstruments
                                      .where((i) => condSearch.isEmpty ||
                                          i['name']!.toLowerCase().contains(condSearch) ||
                                          i['code']!.toLowerCase().contains(condSearch))
                                      .map((inst) => CheckboxListTile(
                                            dense: true,
                                            value: condSelectedCodes.contains(inst['code']),
                                            activeColor: const Color(0xFFF5A623),
                                            checkColor: Colors.black,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                            title: Text(inst['name']!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            subtitle: Text(inst['code']!, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                            onChanged: (v) => setModalState(() {
                                              if (v == true) condSelectedCodes.add(inst['code']!);
                                              else condSelectedCodes.remove(inst['code']!);
                                            }),
                                          ))
                                      .toList(),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              _staffExportCheckbox('Upcoming Scheduled Instruments', Icons.event, 
                  Colors.purple, expUpcoming,
                  (v) => setModalState(() => expUpcoming = v!)),
              _staffExportCheckbox('Overdue Instruments', Icons.warning_amber,
                  Colors.red, expOverdue,
                  (v) => setModalState(() => expOverdue = v!)),
              _staffExportCheckbox('Instruments Currently Out', Icons.outbox,
                  Colors.orange, expOut,
                  (v) => setModalState(() => expOut = v!)),
              const SizedBox(height: 8),
              if (!expCondHistory && !expUpcoming && !expOverdue && !expOut)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Select at least one option to export.',
                      style: TextStyle(color: Colors.red, fontSize: 11)),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (!expCondHistory && !expUpcoming && !expOverdue && !expOut)
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          final types = <ExportType>[];
                          if (expCondHistory) types.add(ExportType.conditionHistory);
                          if (expUpcoming) types.add(ExportType.upcoming);
                          if (expOverdue) types.add(ExportType.overdue);
                          if (expOut) types.add(ExportType.instrumentsOut);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DispatchExportScreen(
                                exportType: types.first,
                                multiExportTypes: types.length > 1 ? types : null,
                                condHistoryFromDate: expCondHistory ? condFromDate : null,
                                condHistoryByDate: expCondHistory ? condByDate : null,
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

  Widget _staffExportCheckbox(String label, IconData icon, Color color,
      bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      dense: true,
      value: value,
      activeColor: const Color(0xFFF5A623),
      checkColor: Colors.black,
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      ]),
      onChanged: onChanged,
    );
  }

  Future<void> _exportSelectedHistory(List<String> codes, Map<String, String> names) async {
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');
      final now = DateTime.now();

      for (final code in codes) {
        final name = names[code] ?? code;
        final safeSheet = name.length > 28 ? name.substring(0, 28) : name;
        final sheet = excel[safeSheet];

        // Title row
        sheet.appendRow([TextCellValue('Instrument History: $name ($code)')]);
        sheet.appendRow([TextCellValue('Export Date'), TextCellValue(DateFormat('MMMM dd, yyyy  hh:mm a').format(now))]);
        sheet.appendRow([TextCellValue('')]);

        // Header
        final headerRow = sheet.maxRows;
        sheet.appendRow([
          TextCellValue('Date/Time'),
          TextCellValue('Event Type'),
          TextCellValue('Details'),
          TextCellValue('Actor'),
        ]);
        final headerStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1A3A5C'),
          fontColorHex: ExcelColor.fromHexString('#F5A623'),
        );
        for (int c = 0; c < 4; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRow)).cellStyle = headerStyle;
        }

        // Data rows
        final history = await DBHelper.instance.getInstrumentHistory(code);
        if (history.isEmpty) {
          sheet.appendRow([TextCellValue('No history recorded'), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
        } else {
          for (final h in history) {
            String ts = '—';
            try {
              ts = DateFormat('MMM dd yyyy  hh:mm a').format(DateTime.parse(h['timestamp'] as String));
            } catch (_) {}
            sheet.appendRow([
              TextCellValue(ts),
              TextCellValue(h['event_type'] as String? ?? '—'),
              TextCellValue(h['event_detail'] as String? ?? '—'),
              TextCellValue(h['actor'] as String? ?? '—'),
            ]);
          }
        }

        sheet.setColumnWidth(0, 22);
        sheet.setColumnWidth(1, 20);
        sheet.setColumnWidth(2, 50);
        sheet.setColumnWidth(3, 18);
      }

      const downloadsPath = '/storage/emulated/0/Download';
      final fileName = 'AMTEC_InstrumentHistory_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx';
      final file = File('$downloadsPath/$fileName');
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to encode Excel');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved: $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _openTypeDetailSheet(String typeName, List<Instrument> units) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _InstrumentTypeDetailSheet(
        typeName: typeName,
        units: units,
        onEditUnit: (unit) {
          Navigator.pop(context);
          _openEditSheet(unit);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeNotifier>().colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _applyFilter(),
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search instruments...',
              hintStyle: TextStyle(color: colors.textHint),
              prefixIcon: Icon(Icons.search, color: colors.accent),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: colors.textHint, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilter();
                      },
                    )
                  : null,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.accent)),
              filled: true,
              fillColor: colors.inputFill,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _filterChip('All', widget.instruments.length, InstrumentFilter.all,
                  colors.accent, colors),
              const SizedBox(width: 8),
              _filterChip('Overdue', _overdueCount, InstrumentFilter.overdue,
                  Colors.red, colors, icon: Icons.alarm),
              const SizedBox(width: 8),
              _filterChip('For Repair', _repairCount, InstrumentFilter.forRepair,
                  Colors.orange, colors, icon: Icons.build),
              const SizedBox(width: 8),
              _filterChip('Condemned', _condemnCount, InstrumentFilter.condemned,
                  Colors.red.shade700, colors, icon: Icons.cancel),
              const SizedBox(width: 8),
              _filterChip('Upcoming', _upcomingCount, InstrumentFilter.upcoming,
                  Colors.purple, colors, icon: Icons.event),
            ],
          ),
        ),
        if (_activeFilter == InstrumentFilter.all)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Text('Sort:', style: TextStyle(color: colors.textHint, fontSize: 11)),
                const SizedBox(width: 8),
                _sortChip('A–Z', InstrumentSort.alphabetical, colors),
                const SizedBox(width: 6),
                _sortChip('Most In Use', InstrumentSort.mostInUse, colors),
                const SizedBox(width: 6),
                _sortChip('Most Overdue', InstrumentSort.mostOverdue, colors),
                const SizedBox(width: 6),
                _sortChip('By Condition', InstrumentSort.conditionPriority, colors),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _activeFilter == InstrumentFilter.all
                      ? '${_groupInstruments(_filtered).length} types · ${_filtered.length} units'
                      : '${_filtered.length} instrument${_filtered.length != 1 ? 's' : ''}',
                  style: TextStyle(color: colors.textHint, fontSize: 11),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showStaffExportMenu(context, colors),
                icon: Icon(Icons.download, size: 14, color: colors.accent),
                label: Text('Export',
                    style: TextStyle(color: colors.accent, fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => widget.onReload(),
            child: _filtered.isEmpty
                ? _buildEmptyState()
                : _activeFilter == InstrumentFilter.all
                    ? _buildGroupedList()
                    : _buildFlatList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final (icon, msg) = switch (_activeFilter) {
      InstrumentFilter.overdue => (Icons.check_circle_outline, 'No overdue instruments 🎉'),
      InstrumentFilter.forRepair => (Icons.build_circle, 'No instruments need repair'),
      InstrumentFilter.condemned => (Icons.verified, 'No instruments condemned'),
      InstrumentFilter.upcoming =>
        (Icons.event_available, 'No upcoming items'),
      _ => (Icons.search_off, 'No instruments found'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  Map<String, List<Instrument>> _groupInstruments(List<Instrument> list) {
    final Map<String, List<Instrument>> groups = {};
    for (final inst in list) {
      groups.putIfAbsent(inst.instrumentName.trim(), () => []).add(inst);
    }
    final entries = groups.entries.toList();
    switch (_activeSort) {
      case InstrumentSort.alphabetical:
        entries.sort((a, b) => a.key.compareTo(b.key));
        break;
      case InstrumentSort.mostInUse:
        entries.sort((a, b) {
          final aI = a.value.where((u) => u.status == 'In Use').length;
          final bI = b.value.where((u) => u.status == 'In Use').length;
          if (bI != aI) return bI.compareTo(aI);
          return a.key.compareTo(b.key);
        });
        break;
      case InstrumentSort.mostOverdue:
        entries.sort((a, b) {
          final aO = a.value.where((u) => u.isOverdue).length;
          final bO = b.value.where((u) => u.isOverdue).length;
          if (bO != aO) return bO.compareTo(aO);
          return a.key.compareTo(b.key);
        });
        break;
      case InstrumentSort.conditionPriority:
        const p = {'Condemning': 0, 'For Repair': 1, 'Functioning': 2};
        entries.sort((a, b) {
          final aP = a.value
              .map((u) => p[u.currentCondition] ?? 3)
              .reduce((x, y) => x < y ? x : y);
          final bP = b.value
              .map((u) => p[u.currentCondition] ?? 3)
              .reduce((x, y) => x < y ? x : y);
          if (aP != bP) return aP.compareTo(bP);
          return a.key.compareTo(b.key);
        });
        break;
    }
    return Map.fromEntries(entries);
  }

  Widget _buildGroupedList() {
    final groups = _groupInstruments(_filtered);
    final groupKeys = groups.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: groupKeys.length,
      itemBuilder: (_, i) {
        final name = groupKeys[i];
        final units = groups[name]!;
        final availableCount = units.where((u) => u.status == 'Available').length;
        final inUseCount = units.where((u) => u.status == 'In Use').length;
        final repairCount = units.where((u) => u.currentCondition == 'For Repair').length;
        final condemnCount = units.where((u) => u.currentCondition == 'Condemning').length;
        final overdueCount = units.where((u) => u.isOverdue).length;
        final upcomingCount =
            units.where((u) => u.isUpcoming(withinDays: _upcomingWindowDays)).length;
        final isExpanded = _expandedGroups.contains(name);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A5C),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: condemnCount > 0
                  ? Colors.red.withValues(alpha: 0.5)
                  : repairCount > 0
                      ? Colors.orange.withValues(alpha: 0.5)
                      : overdueCount > 0
                          ? Colors.red.withValues(alpha: 0.3)
                          : upcomingCount > 0
                              ? Colors.purple.withValues(alpha: 0.35)
                              : inUseCount > 0
                                  ? Colors.orange.withValues(alpha: 0.25)
                                  : const Color(0xFF1E3A5F),
            ),
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedGroups.remove(name);
                  } else {
                    _expandedGroups.add(name);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5A623).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.build_circle,
                            color: Color(0xFFF5A623), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              _countChip('$availableCount Available', Colors.green),
                              if (inUseCount > 0)
                                _countChip('$inUseCount In Use', Colors.orange),
                              _countChip('${units.length} Total', Colors.white38),
                              if (overdueCount > 0)
                                _priorityChip('$overdueCount Overdue', Colors.red, Icons.alarm),
                              if (repairCount > 0)
                                _priorityChip('$repairCount Repair', Colors.orange, Icons.build),
                              if (condemnCount > 0)
                                _priorityChip(
                                    '$condemnCount Condemn', Colors.red.shade700, Icons.cancel),
                              if (upcomingCount > 0)
                                _priorityChip(
                                    '$upcomingCount Upcoming', Colors.purple, Icons.event),
                            ]),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline,
                            color: Colors.white38, size: 20),
                        tooltip: 'Type health summary',
                        splashRadius: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _openTypeDetailSheet(name, units),
                      ),
                      Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: const Color(0xFFF5A623)),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const Divider(color: Color(0xFF1E3A5F), height: 1),
                ...units.map((unit) => _buildUnitRow(unit)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlatList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final unit = _filtered[i];
        return _activeFilter == InstrumentFilter.upcoming
            ? _buildUpcomingCard(unit)
            : _buildBarcodeCard(unit);
      },
    );
  }

  Widget _buildBarcodeCard(Instrument unit) {
    final isRepairFilter = _activeFilter == InstrumentFilter.forRepair;
    final isCondemnFilter = _activeFilter == InstrumentFilter.condemned;

    final Color accentColor = isCondemnFilter
        ? Colors.red.shade700
        : isRepairFilter
            ? Colors.orange
            : Colors.red;

    final String badgeLabel = isCondemnFilter
        ? 'CONDEMNED'
        : isRepairFilter
            ? 'FOR REPAIR'
            : '${unit.daysOut}d OVERDUE';

    final IconData badgeIcon = isCondemnFilter
        ? Icons.cancel
        : isRepairFilter
            ? Icons.build
            : Icons.alarm;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showUnitHistory(unit),
        onLongPress: () => _openEditSheet(unit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code, color: accentColor, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          unit.instrumentCode,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: accentColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, color: accentColor, size: 11),
                        const SizedBox(width: 4),
                        Text(badgeLabel,
                            style: TextStyle(
                                color: accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.history,
                        color: Colors.white38, size: 18),
                    tooltip: 'History',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showUnitHistory(unit),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_note,
                        color: Color(0xFFF5A623), size: 18),
                    tooltip: 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _openEditSheet(unit),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(unit.instrumentName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 6),
              if (unit.serialNumber != null && unit.serialNumber!.isNotEmpty)
                _infoLine(Icons.tag, 'S/N: ${unit.serialNumber}'),
              if (unit.location != null && unit.location!.isNotEmpty)
                _infoLine(Icons.location_on, unit.location!),
              if (unit.lastTouchBy != null)
                _infoLine(Icons.person, 'Last used by: ${unit.lastTouchBy}'),
              if (unit.lastTouchDate != null)
                _infoLine(
                  Icons.access_time,
                  _activeFilter == InstrumentFilter.overdue
                      ? 'Out since: ${_formatDate(unit.lastTouchDate)} (${unit.daysOut} days)'
                      : _formatDate(unit.lastTouchDate),
                ),
              if (unit.notes != null && unit.notes!.isNotEmpty)
                _infoLine(Icons.notes, unit.notes!),
              if (unit.scheduledRepairDate != null)
                _infoLine(Icons.build, 'Repair scheduled: ${_formatDate(unit.scheduledRepairDate)}'),
              if (unit.scheduledCondemnDate != null)
                _infoLine(Icons.cancel, 'Condemn scheduled: ${_formatDate(unit.scheduledCondemnDate)}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statusBadge(unit.status),
                  const SizedBox(width: 6),
                  _conditionBadge(unit.currentCondition),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FIX 6: _buildUpcomingCard now handles no-date case (bad condition, no schedule set)
  Widget _buildUpcomingCard(Instrument unit) {
    final repairDays = unit.daysUntilRepair;
    final condemnDays = unit.daysUntilCondemn;
    final hasNoDate = unit.needsSchedule;

    final days = [
      ?repairDays,
      ?condemnDays,
    ];
    final minDays = days.isEmpty ? 9998 : days.reduce((a, b) => a < b ? a : b);

    final borderColor = hasNoDate
        ? (unit.currentCondition == 'Condemning'
            ? Colors.red.withValues(alpha: 0.6)
            : Colors.orange.withValues(alpha: 0.6))
        : (minDays <= 7
            ? Colors.red.withValues(alpha: 0.5)
            : minDays <= 14
                ? Colors.orange.withValues(alpha: 0.5)
                : Colors.green.withValues(alpha: 0.5));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showUnitHistory(unit),
        onLongPress: () => _openEditSheet(unit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5, right: 10),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasNoDate
                        ? (unit.currentCondition == 'Condemning'
                            ? Colors.red
                            : Colors.orange)
                        : (minDays <= 7
                            ? Colors.red
                            : minDays <= 14
                                ? Colors.orange
                                : Colors.green)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(unit.instrumentName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    Row(children: [
                      const Icon(Icons.qr_code, color: Colors.white38, size: 11),
                      const SizedBox(width: 4),
                      Text(unit.instrumentCode,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),
                    if (repairDays != null)
                      _scheduledEventRow(Icons.build, 'Repair scheduled',
                          _formatDate(unit.scheduledRepairDate), repairDays, Colors.orange),
                        if (unit.scheduledCondemnDate != null && condemnDays != null)
                          _scheduledEventRow(Icons.cancel, 'Condemn',
                          _formatDate(unit.scheduledCondemnDate), condemnDays, Colors.red),
                        if (unit.lastCalibratedDate != null) ...[
                          const SizedBox(height: 4),
                          _scheduledEventRow(
                            Icons.science,
                            'Calibration due',
                            unit.lastCalibratedDate!.substring(0, 10),
                            unit.daysUntilCalibrationDue ?? 0,
                            Colors.blue,
                          ),
                        ],
                    // FIX 6: Show "needs scheduling" prompt when no date set
                    if (hasNoDate) ...[
                      Row(children: [
                        Icon(
                          unit.currentCondition == 'Condemning' ? Icons.cancel : Icons.build,
                          color: unit.currentCondition == 'Condemning'
                              ? Colors.red.shade300
                              : Colors.orange.shade300,
                          size: 13,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          unit.currentCondition == 'Condemning'
                              ? 'Condemning — no date set'
                              : 'For Repair — no date set',
                          style: TextStyle(
                            color: unit.currentCondition == 'Condemning'
                                ? Colors.red.shade300
                                : Colors.orange.shade300,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      const Text('Tap edit to set a scheduled date',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                    if (unit.notes != null && unit.notes!.isNotEmpty)
                      _infoLine(Icons.notes, unit.notes!),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white38, size: 18),
                tooltip: 'History',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showUnitHistory(unit),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Color(0xFFF5A623), size: 20),
                tooltip: 'Edit schedule',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _openEditSheet(unit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scheduledEventRow(
      IconData icon, String label, String date, int daysAway, Color color) {
    final uc =
        daysAway <= 7 ? Colors.red : daysAway <= 14 ? Colors.orange : Colors.green;
    final daysLabel =
        daysAway <= 0 ? 'OVERDUE' : daysAway == 1 ? 'TOMORROW' : '$daysAway days away';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Expanded(
              child: Text('$label: $date',
                  style: const TextStyle(color: Colors.white70, fontSize: 12))),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: uc.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: uc),
            ),
            child: Text(daysLabel,
                style: TextStyle(
                    color: uc, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitRow(Instrument unit) {
    final isOverdue = unit.isOverdue;
    final days = unit.daysOut;
    final hasUpcoming = unit.isUpcoming(withinDays: _upcomingWindowDays);
    return Container(
      decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: Color(0xFF1E3A5F), width: 0.5))),
      child: InkWell(
        onTap: () => _showUnitHistory(unit),
        onLongPress: () => _openEditSheet(unit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 6, right: 10),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _statusColor(unit.status)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(unit.instrumentCode,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13))),
                      _statusBadge(unit.status),
                      if (unit.currentCondition != 'Functioning') ...[
                        const SizedBox(width: 4),
                        _conditionBadge(unit.currentCondition),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    if (unit.serialNumber != null && unit.serialNumber!.isNotEmpty)
                      _infoLine(Icons.qr_code, 'S/N: ${unit.serialNumber}'),
                    if (unit.location != null && unit.location!.isNotEmpty)
                      _infoLine(Icons.location_on, unit.location!),
                    _infoLine(Icons.touch_app,
                        unit.lastTouchBy != null ? 'Last used by: ${unit.lastTouchBy}' : 'Never used'),
                    if (unit.lastTouchDate != null)
                      _infoLine(
                          Icons.access_time,
                          isOverdue
                              ? 'Out since: ${_formatDate(unit.lastTouchDate)} ($days days) ⚠️'
                              : _formatDate(unit.lastTouchDate)),
                    if (unit.notes != null && unit.notes!.isNotEmpty)
                      _infoLine(Icons.notes, unit.notes!),
                    if (hasUpcoming) ...[
                      if (unit.scheduledRepairDate != null)
                        _infoLine(Icons.build,
                            'Repair: ${_formatDate(unit.scheduledRepairDate)} (${(unit.daysUntilRepair ?? 0) >= 0 ? '${unit.daysUntilRepair}d away' : 'OVERDUE'})'),
                      if (unit.scheduledCondemnDate != null)
                        _infoLine(Icons.cancel,
                            'Condemn: ${_formatDate(unit.scheduledCondemnDate)} (${(unit.daysUntilCondemn ?? 0) >= 0 ? '${unit.daysUntilCondemn}d away' : 'OVERDUE'})'),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white38, size: 18),
                tooltip: 'History',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showUnitHistory(unit),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_note, color: Color(0xFFF5A623), size: 18),
                tooltip: 'Edit',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _openEditSheet(unit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Chip helpers ──────────────────────────────────────────────────────────

  Widget _filterChip(String label, int count, InstrumentFilter filter,
      Color activeColor, AppColors colors, {IconData? icon}) {
    final selected = _activeFilter == filter;
    final hasItems = count > 0;
    return GestureDetector(
      onTap: () => _setFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.2) : colors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? activeColor
                : hasItems && filter != InstrumentFilter.all
                    ? activeColor.withValues(alpha: 0.4)
                    : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 12,
                  color: selected
                      ? activeColor
                      : hasItems
                          ? activeColor.withValues(alpha: 0.7)
                          : colors.textHint),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected
                        ? activeColor
                        : hasItems && filter != InstrumentFilter.all
                            ? activeColor.withValues(alpha: 0.8)
                            : colors.textSecondary,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
            ),
            if (filter != InstrumentFilter.all) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: hasItems
                      ? activeColor.withValues(alpha: selected ? 0.3 : 0.15)
                      : colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(' $count',
                    style: TextStyle(
                        color: hasItems ? activeColor : colors.textHint,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, InstrumentSort sort, AppColors colors) {
    final selected = _activeSort == sort;
    return GestureDetector(
      onTap: () => _setSort(sort),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: selected ? colors.accent : colors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? colors.accent : colors.textHint,
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _countChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      );

  Widget _priorityChip(String label, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.7))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color)),
      child: Text(status,
          style:
              TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _conditionBadge(String condition) {
    final color = _conditionColor(condition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color)),
      child: Text(condition,
          style:
              TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Icon(icon, size: 11, color: Colors.white38),
          const SizedBox(width: 5),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11))),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SUB-TAB B — UPCOMING  (FIX 3: saves to Downloads + FIX 6: shows no-date items)
// ══════════════════════════════════════════════════════════════════════════════

class _UpcomingSubTab extends StatefulWidget {
  final List<Instrument> instruments;
  final VoidCallback onReload;
  const _UpcomingSubTab({required this.instruments, required this.onReload});

  @override
  State<_UpcomingSubTab> createState() => _UpcomingSubTabState();
}

class _UpcomingSubTabState extends State<_UpcomingSubTab> {
  static const int _windowDays = 30;

  @override
  void didUpdateWidget(_UpcomingSubTab old) {
    super.didUpdateWidget(old);
    // Trigger rebuild when instruments list changes (e.g. after edit sheet saves)
    if (old.instruments != widget.instruments) {
      setState(() {});
    }
  }

  // FIX 6: Include all For Repair / Condemning instruments, not just those with dates.
  // Instruments with no date sort to the bottom (after scheduled ones).
  List<Instrument> get _upcoming => widget.instruments
      .where((i) => i.isUpcoming(withinDays: _windowDays))
      .toList()
    ..sort((a, b) {
      // No-date items go to bottom
      final aNoDate = (a.needsSchedule && a.daysUntilRepair == null && a.daysUntilCondemn == null) ? 1 : 0;
      final bNoDate = (b.needsSchedule && b.daysUntilRepair == null && b.daysUntilCondemn == null) ? 1 : 0;
      if (aNoDate != bNoDate) return aNoDate - bNoDate;
      return _minDaysAway(a).compareTo(_minDaysAway(b));
    });

  List<Instrument> get _overdueScheduled {
    // Instruments past their scheduled repair/condemn date
    final scheduledOverdue = _upcoming
        .where((i) =>
            (i.daysUntilRepair != null && i.daysUntilRepair! <= 0) ||
            (i.daysUntilCondemn != null && i.daysUntilCondemn! <= 0))
        .toList();
    // Instruments overdue for return from dispatch (In Use past threshold)
    final dispatchOverdue = widget.instruments
        .where((i) => i.isOverdue && !scheduledOverdue.any((s) => s.instrumentCode == i.instrumentCode))
        .toList();
    return [...scheduledOverdue, ...dispatchOverdue];
  }

  int _minDaysAway(Instrument i) {
    final r = i.daysUntilRepair;
    final c = i.daysUntilCondemn;
    if (r == null && c == null) return 9998;
    if (r == null) return c!;
    if (c == null) return r;
    return r < c ? r : c;
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    try {
      final d = DateTime.parse(s);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  Color _urgencyColor(int daysAway) {
    if (daysAway <= 0) return Colors.red;
    if (daysAway <= 7) return Colors.red;
    if (daysAway <= 14) return Colors.orange;
    return Colors.green;
  }

  void _openEditSheet(Instrument unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) =>
          _InstrumentEditSheet(instrument: unit, onSaved: widget.onReload),
    );
  }

  Widget _checkboxTile({
    required BuildContext ctx,
    required bool value,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required ValueChanged<bool?> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: value ? color.withValues(alpha: 0.1) : const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: value ? color.withValues(alpha: 0.6) : const Color(0xFF1E3A5F),
              width: value ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: value ? color : Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: value ? color : Colors.white54,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            Text(subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            side: BorderSide(color: value ? color : Colors.white38),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ]),
      ),
    );
  }

  void _writeHeaders(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E3A5F'),
        fontColorHex: ExcelColor.fromHexString('#F5A623'),
      );
    }
  }

  void _showSuccessDialog(String path) {
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
            const Text('File saved to Downloads folder:',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
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

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final items = _upcoming;
    final overdueItems = _overdueScheduled;
    // FIX 6: separate counts for display
    final noDateCount = items.where((i) => i.needsSchedule && i.daysUntilRepair == null && i.daysUntilCondemn == null).length;

    return Column(
      children: [
        if (overdueItems.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 60),
            child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${overdueItems.length} instrument${overdueItems.length > 1 ? 's are' : ' is'} past their scheduled date!',
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ]),
          ),
          ),

        // FIX 6: Banner for no-date instruments
        if (noDateCount > 0)
          Container(
            margin: EdgeInsets.fromLTRB(12, overdueItems.isNotEmpty ? 8 : 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$noDateCount instrument${noDateCount > 1 ? 's need' : ' needs'} a schedule date set',
                  style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Text(
                items.isEmpty
                    ? 'No upcoming schedules'
                    : '${items.length} instrument${items.length != 1 ? 's' : ''} scheduled',
                style: TextStyle(
                    color: items.isEmpty ? Colors.white38 : Colors.white70,
                    fontSize: 12),
              ),
              const Spacer(),
              
            ],
          ),
        ),

        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text(
                          'No instruments scheduled for repair or condemn',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                          textAlign: TextAlign.center),
                      SizedBox(height: 6),
                      Text(
                          'Use the edit button on any instrument to set a schedule',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                          textAlign: TextAlign.center),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => widget.onReload(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final unit = items[i];
                      final repairDays = unit.daysUntilRepair;
                      final condemnDays = unit.daysUntilCondemn;
                      final hasNoDate = unit.needsSchedule &&
                          repairDays == null && condemnDays == null;
                      final minDays = _minDaysAway(unit);
                      final borderColor = hasNoDate
                          ? (unit.currentCondition == 'Condemning'
                              ? Colors.red
                              : Colors.orange)
                          : _urgencyColor(minDays);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A3A5C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor.withValues(alpha: 0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(top: 5, right: 10),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle, color: borderColor),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(unit.instrumentName,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Row(children: [
                                      const Icon(Icons.qr_code,
                                          color: Colors.white38, size: 11),
                                      const SizedBox(width: 4),
                                      Text(unit.instrumentCode,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    ]),
                                    const SizedBox(height: 8),
                                    if (repairDays != null)
                                      _scheduleRow(Icons.build, 'Repair',
                                          _formatDate(unit.scheduledRepairDate),
                                          repairDays, Colors.orange),
                                    if (condemnDays != null)
                                      _scheduleRow(Icons.cancel, 'Condemn',
                                          _formatDate(unit.scheduledCondemnDate),
                                          condemnDays, Colors.red),
                                    // FIX 6: no-date prompt
                                    if (hasNoDate) ...[
                                      Row(children: [
                                        Icon(
                                          unit.currentCondition == 'Condemning'
                                              ? Icons.cancel
                                              : Icons.build,
                                          color: unit.currentCondition == 'Condemning'
                                              ? Colors.red.shade300
                                              : Colors.orange.shade300,
                                          size: 13,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          unit.currentCondition == 'Condemning'
                                              ? 'Condemning — no date set'
                                              : 'For Repair — no date set',
                                          style: TextStyle(
                                            color: unit.currentCondition == 'Condemning'
                                                ? Colors.red.shade300
                                                : Colors.orange.shade300,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 2),
                                      const Text('Tap edit to set a scheduled date',
                                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                                    ],
                                    if (unit.notes != null && unit.notes!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(children: [
                                          const Icon(Icons.notes,
                                              size: 11, color: Colors.white38),
                                          const SizedBox(width: 5),
                                          Expanded(
                                              child: Text(unit.notes!,
                                                  style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 11))),
                                        ]),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_note,
                                    color: Color(0xFFF5A623), size: 20),
                                tooltip: 'Edit schedule',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _openEditSheet(unit),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _scheduleRow(
      IconData icon, String label, String date, int daysAway, Color color) {
    final uc = _urgencyColor(daysAway);
    final daysLabel =
        daysAway <= 0 ? 'OVERDUE' : daysAway == 1 ? 'TOMORROW' : '$daysAway days away';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 6),
        Expanded(
            child: Text('$label: $date',
                style: const TextStyle(color: Colors.white70, fontSize: 12))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: uc.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: uc),
          ),
          child: Text(daysLabel,
              style: TextStyle(
                  color: uc, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INSTRUMENT TYPE DETAIL SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _InstrumentTypeDetailSheet extends StatefulWidget {
  final String typeName;
  final List<Instrument> units;
  final void Function(Instrument) onEditUnit;
  const _InstrumentTypeDetailSheet(
      {required this.typeName, required this.units, required this.onEditUnit});

  @override
  State<_InstrumentTypeDetailSheet> createState() =>
      _InstrumentTypeDetailSheetState();
}

class _InstrumentTypeDetailSheetState
    extends State<_InstrumentTypeDetailSheet> {
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final codes = widget.units.map((u) => u.instrumentCode).toSet();
    final allDispatches = await DBHelper.instance.getAllDispatches();
    final results = <Map<String, dynamic>>[];
    for (final dispatch in allDispatches) {
      if (dispatch.id == null) continue;
      final items = await DBHelper.instance.getDispatchItems(dispatch.id!);
      final matched =
          items.where((it) => codes.contains(it.instrumentCode)).toList();
      if (matched.isEmpty) continue;
      results.add({'dispatch': dispatch, 'items': matched});
    }
    results.sort((a, b) {
      final da = (a['dispatch'].dateOut as String?) ?? '';
      final db_ = (b['dispatch'].dateOut as String?) ?? '';
      return db_.compareTo(da);
    });
    if (mounted) {
      setState(() {
        _history = results;
        _loadingHistory = false;
      });
    }
  }

  Color _conditionColor(String? c) {
    switch (c) {
      case 'Functioning': return Colors.green;
      case 'For Repair': return Colors.orange;
      case 'Condemning': return Colors.red;
      default: return Colors.white38;
    }
  }

  String _fmt(String? s) {
    if (s == null) return '—';
    try {
      final d = DateTime.parse(s);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.units;
    final total = units.length;
    final available = units.where((u) => u.status == 'Available').length;
    final inUse = units.where((u) => u.status == 'In Use').length;
    final overdue = units.where((u) => u.isOverdue).length;
    final forRepair = units.where((u) => u.currentCondition == 'For Repair').length;
    final condemned = units.where((u) => u.currentCondition == 'Condemning').length;
    final overdueUnits = units.where((u) => u.isOverdue).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => SingleChildScrollView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99)))),
            Text(widget.typeName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 4),
            Text('$total unit${total != 1 ? 's' : ''} registered',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            _sectionLabel('HEALTH SUMMARY'),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.35,
              children: [
                _statCard('$available', 'Available', Colors.green, Icons.check_circle_outline),
                _statCard('$inUse', 'In Use', Colors.orange, Icons.outbox),
                _statCard('$total', 'Total', Colors.white38, Icons.inventory_2_outlined),
                _statCard('$overdue', 'Overdue', Colors.red, Icons.alarm),
                _statCard('$forRepair', 'For Repair', Colors.orange, Icons.build),
                _statCard('$condemned', 'Condemned', Colors.red.shade700, Icons.cancel),
              ],
            ),
            const SizedBox(height: 20),
            if (overdueUnits.isNotEmpty) ...[
              _sectionLabel('OVERDUE UNITS'),
              const SizedBox(height: 8),
              ...overdueUnits.map((u) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.4))),
                    child: Row(children: [
                      const Icon(Icons.alarm, color: Colors.red, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(u.instrumentCode,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            if (u.lastTouchBy != null)
                              Text('With: ${u.lastTouchBy}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11)),
                          ])),
                      Text('${u.daysOut}d out',
                          style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                  )),
              const SizedBox(height: 20),
            ],
            _sectionLabel('ALL UNITS (${units.length})'),
            const SizedBox(height: 8),
            ...units.map((u) {
              final cc = _conditionColor(u.currentCondition);
              return GestureDetector(
                onTap: () => _showUnitHistory(u),
                onLongPress: () => widget.onEditUnit(u),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A5F))),
                  child: Row(children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: u.status == 'Available'
                                ? Colors.green
                                : Colors.orange)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(u.instrumentCode,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                          if (u.location != null && u.location!.isNotEmpty)
                            Text(u.location!,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10)),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: cc.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: cc)),
                      child: Text(u.currentCondition,
                          style: TextStyle(
                              color: cc,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.history, color: Colors.white24, size: 14),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 20),
            _sectionLabel(
                'DISPATCH HISTORY (${_history.length} dispatch${_history.length != 1 ? 'es' : ''})'),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                          color: Color(0xFFF5A623), strokeWidth: 2)))
            else if (_history.isEmpty)
              Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A5F))),
                  child: const Center(
                      child: Text(
                          'No dispatch history for this instrument type.',
                          style: TextStyle(color: Colors.white38, fontSize: 12))))
            else
              ..._history.map((entry) {
                final dispatch = entry['dispatch'];
                final items = entry['items'] as List;
                final isOut = dispatch.dateIn == null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isOut
                              ? Colors.orange.withValues(alpha: 0.35)
                              : const Color(0xFF1E3A5F))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(dispatch.dispatchNo,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: isOut
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color: isOut ? Colors.orange : Colors.green)),
                            child: Text(isOut ? 'Out' : 'Returned',
                                style: TextStyle(
                                    color: isOut ? Colors.orange : Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(dispatch.testEngineer,
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        Text(
                            _fmt(dispatch.dateOut) +
                                (dispatch.dateIn != null
                                    ? '  →  ${_fmt(dispatch.dateIn)}'
                                    : ''),
                            style: const TextStyle(color: Colors.white38, fontSize: 10)),
                        const SizedBox(height: 8),
                        Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: items.map<Widget>((item) {
                              final rc = item.returnCondition as String?;
                              final cc2 = item.currentCondition as String?;
                              final condColor = _conditionColor(rc ?? cc2);
                              return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: condColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: condColor.withValues(alpha: 0.5))),
                                  child: Text(item.instrumentCode,
                                      style: TextStyle(
                                          color: condColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)));
                            }).toList()),
                      ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  void _showUnitHistory(Instrument unit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A3A5C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _UnitHistorySheet(
          unit: unit, onEdit: () => widget.onEditUnit(unit)),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Color(0xFFF5A623),
          fontSize: 10,
          letterSpacing: 3,
          fontWeight: FontWeight.bold));

  Widget _statCard(String value, String label, Color color, IconData icon) =>
      Container(
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// UNIT HISTORY SHEET — per-instrument event log
// ══════════════════════════════════════════════════════════════════════════════

class _UnitHistorySheet extends StatefulWidget {
  final Instrument unit;
  final VoidCallback onEdit;
  const _UnitHistorySheet({required this.unit, required this.onEdit});

  @override
  State<_UnitHistorySheet> createState() => _UnitHistorySheetState();
}

class _UnitHistorySheetState extends State<_UnitHistorySheet> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DBHelper.instance
        .getInstrumentHistory(widget.unit.instrumentCode);
    if (mounted) setState(() { _history = rows; _loading = false; });
  }

  String _fmtTs(String? ts) {
    if (ts == null) return '—';
    try {
      final d = DateTime.parse(ts);
      return '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return ts; }
  }

  (IconData, Color) _eventStyle(String? type) {
    switch (type) {
      case 'added': return (Icons.add_circle_outline, Colors.green);
      case 'dispatched': return (Icons.outbox, const Color(0xFFF5A623));
      case 'borrowed': return (Icons.school, Colors.purple);
      case 'returned': return (Icons.login, Colors.teal);
      case 'condition_changed': return (Icons.swap_horiz, Colors.orange);
      case 'location_changed': return (Icons.location_on, Colors.blue);
      case 'scheduled': return (Icons.event, Colors.red);
      default: return (Icons.history, Colors.white38);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99)))),
                Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(unit.instrumentCode,
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(unit.instrumentName,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  )),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onEdit();
                    },
                    icon: const Icon(Icons.edit_note, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF5A623),
                      side: const BorderSide(color: Color(0xFFF5A623)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                // Current info chips
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip(unit.currentCondition, _conditionChipColor(unit.currentCondition)),
                  _chip(unit.status, unit.status == 'Available' ? Colors.green : Colors.orange),
                  if (unit.location != null && unit.location!.isNotEmpty)
                    _chip(unit.location!, Colors.white38),
                ]),
                const SizedBox(height: 12),
                const Text('INSTRUMENT HISTORY',
                    style: TextStyle(color: Color(0xFFF5A623), fontSize: 10,
                        letterSpacing: 3, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5A623)))
                : _history.isEmpty
                    ? const Center(child: Text('No history recorded yet.',
                        style: TextStyle(color: Colors.white38, fontSize: 13)))
                    : ListView.builder(
                        controller: sc,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        itemCount: _history.length,
                        itemBuilder: (_, i) {
                          final row = _history[i];
                          final (icon, color) = _eventStyle(row['event_type'] as String?);
                          final isLast = i == _history.length - 1;
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(children: [
                                  Container(width: 28, height: 28,
                                      decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: color.withValues(alpha: 0.5))),
                                      child: Icon(icon, color: color, size: 14)),
                                  if (!isLast)
                                    Expanded(child: Container(width: 1.5,
                                        color: const Color(0xFF1E3A5F))),
                                ]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(row['event_detail'] ?? row['event_type'] ?? '',
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 13)),
                                        const SizedBox(height: 2),
                                        Row(children: [
                                          Text(_fmtTs(row['timestamp'] as String?),
                                              style: const TextStyle(
                                                  color: Colors.white38, fontSize: 10)),
                                          if (row['actor'] != null && (row['actor'] as String).isNotEmpty) ...[
                                            const Text('  ·  ',
                                                style: TextStyle(color: Colors.white24, fontSize: 10)),
                                            Text(row['actor'] as String,
                                                style: const TextStyle(
                                                    color: Colors.white38, fontSize: 10)),
                                          ],
                                        ]),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Color _conditionChipColor(String c) {
    switch (c) {
      case 'Functioning': return Colors.green;
      case 'For Repair': return Colors.orange;
      case 'Condemning': return Colors.red;
      default: return Colors.white38;
    }
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5))),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// INSTRUMENT EDIT SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _InstrumentEditSheet extends StatefulWidget {
  final Instrument instrument;
  final VoidCallback onSaved;
  const _InstrumentEditSheet({required this.instrument, required this.onSaved});

  @override
  State<_InstrumentEditSheet> createState() => _InstrumentEditSheetState();
}

class _InstrumentEditSheetState extends State<_InstrumentEditSheet> {
  late String _condition;
  late TextEditingController _locationCtrl;
  late TextEditingController _notesCtrl;
  DateTime? _repairDate;
  DateTime? _condemnDate;
  bool _saving = false;
  String? _changeReason; // reason for condition change (shown in history)
  bool _pendingAdminApproval = false; // true when Condemning → other needs admin

  @override
  void initState() {
    super.initState();
    _condition = widget.instrument.currentCondition;
    _locationCtrl = TextEditingController(text: widget.instrument.location ?? '');
    _notesCtrl = TextEditingController(text: widget.instrument.notes ?? '');
    _repairDate = _parseDate(widget.instrument.scheduledRepairDate);
    _condemnDate = _parseDate(widget.instrument.scheduledCondemnDate);
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Not set';
    return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _pickDate({required bool isRepair}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isRepair ? _repairDate : _condemnDate) ??
          now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
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
      if (isRepair) {
        _repairDate = picked;
      } else {
        _condemnDate = picked;
      }
    });
  }

  void _handleConditionTap(String newCondition) {
    if (newCondition == _condition) return;
    final oldCondition = widget.instrument.currentCondition;

    // Condemning → anything requires admin approval
    if (oldCondition == 'Condemning' && newCondition != 'Condemning') {
      _showCondemnRevertDialog(newCondition);
      return;
    }

    // For Repair → Functioning requires a reason
    if (oldCondition == 'For Repair' && newCondition == 'Functioning') {
      _showRepairReasonDialog(newCondition);
      return;
    }

    // For Repair or Condemning → require reason
    if (newCondition == 'For Repair') {
      _showSetConditionReasonDialog(newCondition, 'For Repair',
          'What is broken or needs repair?');
      return;
    }
    if (newCondition == 'Condemning') {
      _showSetConditionReasonDialog(newCondition, 'Condemning',
          'Why is this instrument being condemned?');
      return;
    }
    if (newCondition == 'For Calibration') {
      _showSetConditionReasonDialog(newCondition, 'For Calibration',
          'Why is this instrument being sent for calibration?');
      return;
    }

    // All other changes apply directly
    setState(() {
      _condition = newCondition;
      _changeReason = null;
      _pendingAdminApproval = false;
      if (newCondition == 'Functioning') {
        _repairDate = null;
        _condemnDate = null;
      }
    });
  }

  void _showSetConditionReasonDialog(
      String newCondition, String conditionLabel, String prompt) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Set to $conditionLabel',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Describe the issue...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFF5A623))),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _condition = newCondition;
                _changeReason = reasonCtrl.text.trim();
                _pendingAdminApproval = false;
                if (newCondition == 'For Repair') _condemnDate = null;
                if (newCondition == 'Condemning') _repairDate = null;
              });
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5A623),
                foregroundColor: Colors.black),
            child: const Text('CONFIRM',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRepairReasonDialog(String newCondition) {
    final reasonCtrl = TextEditingController();
    bool fixedSelected = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A5C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Reason for Change',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Why is this instrument being set to Functioning?',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => setD(() => fixedSelected = !fixedSelected),
                child: Row(children: [
                  Icon(fixedSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      color: const Color(0xFFF5A623), size: 20),
                  const SizedBox(width: 8),
                  const Text('Instrument Fixed', style: TextStyle(color: Colors.white)),
                ]),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Other reason (optional)...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFF5A623))),
                  filled: true,
                  fillColor: const Color(0xFF0D1B2A),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                final reason = fixedSelected
                    ? 'Instrument Fixed${reasonCtrl.text.trim().isNotEmpty ? ' — ${reasonCtrl.text.trim()}' : ''}'
                    : reasonCtrl.text.trim();
                if (reason.isEmpty) return;
                Navigator.pop(ctx);
                setState(() {
                  _condition = newCondition;
                  _changeReason = reason;
                  _pendingAdminApproval = false;
                  _repairDate = null;
                  _condemnDate = null;
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: Colors.black),
              child: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCondemnRevertDialog(String newCondition) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Admin Approval Required',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Reverting from Condemning requires admin approval.\n\nProvide a reason and submit for review:',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason for reverting condemn...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFF5A623))),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _condition = newCondition;
                _changeReason = 'Revert from Condemning — ${reasonCtrl.text.trim()}';
                _pendingAdminApproval = true;
                _repairDate = null;
                _condemnDate = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Submitted for admin approval — condition is pending'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3)));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white),
            child: const Text('SUBMIT FOR APPROVAL',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  void _showCalibrateDialog() {
    final notesCtrl = TextEditingController();
    DateTime? nextDueDate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A5C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Calibrate Instrument',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Do you want to mark this instrument as calibrated today?',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text('Calibration notes:',
                style: TextStyle(color: Color(0xFFF5A623), fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What was calibrated? Any readings, notes...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFF5A623))),
                filled: true,
                fillColor: const Color(0xFF0D1B2A),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Next calibration due (optional):',
                style: TextStyle(color: Color(0xFFF5A623), fontSize: 11)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx2,
                  initialDate: DateTime.now().add(const Duration(days: 365)),
                  firstDate: DateTime.now().add(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                  builder: (c, child) => Theme(
                    data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                            primary: Color(0xFFF5A623),
                            onPrimary: Colors.black,
                            surface: Color(0xFF1A3A5C))),
                    child: child!,
                  ),
                );
                if (picked != null) setSt(() => nextDueDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: nextDueDate != null
                      ? const Color(0xFFF5A623).withValues(alpha: 0.08)
                      : const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: nextDueDate != null
                          ? const Color(0xFFF5A623)
                          : const Color(0xFF1E3A5F)),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today,
                      color: nextDueDate != null ? const Color(0xFFF5A623) : Colors.white38,
                      size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nextDueDate != null
                          ? '${nextDueDate!.day}/${nextDueDate!.month}/${nextDueDate!.year}'
                          : 'Tap to set next due date',
                      style: TextStyle(
                          color: nextDueDate != null ? const Color(0xFFF5A623) : Colors.white38,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (nextDueDate != null)
                    GestureDetector(
                      onTap: () => setSt(() => nextDueDate = null),
                      child: const Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                ]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx2);
              final prefs = await SharedPreferences.getInstance();
              final actor = prefs.getString('user_name') ?? '';
              final today = DateTime.now().toIso8601String().split('T').first;
              final notes = notesCtrl.text.trim();
              final nextDueStr = nextDueDate != null
                  ? nextDueDate!.toIso8601String().split('T').first
                  : null;
              await DBHelper.instance.updateInstrumentDetails(
                code: widget.instrument.instrumentCode,
                lastCalibratedDate: today,
                calibrationNotes: notes.isEmpty ? null : notes,
                nextCalibrationDue: nextDueStr,
                condition: widget.instrument.currentCondition == 'For Calibration'
                    ? 'Functioning'
                    : null,
              );
              await DBHelper.instance.logInstrumentEvent(
                instrumentCode: widget.instrument.instrumentCode,
                eventType: 'calibrated',
                eventDetail: 'Instrument calibrated on $today'
                    '${notes.isNotEmpty ? " — Notes: $notes" : ""}'
                    '${nextDueStr != null ? " — Next due: $nextDueStr" : ""}',
                actor: actor,
              );
              if (mounted) {
                widget.onSaved();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Instrument marked as calibrated'),
                    backgroundColor: Colors.blue,
                    duration: Duration(seconds: 2)));
              }
            },
            child: const Text('Calibrate'),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_condition == 'For Repair' &&
        _repairDate == null &&
        _condition != widget.instrument.currentCondition) {
      // Only enforce date when user is actively changing TO For Repair
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please set a scheduled repair date'),
          backgroundColor: Colors.orange));
      return;
    }
    if (_condition == 'Condemning' &&
        _condemnDate == null &&
        _condition != widget.instrument.currentCondition) {
      // Only enforce date when user is actively changing TO Condemning
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please set a scheduled condemn date'),
          backgroundColor: Colors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final actor = prefs.getString('user_name') ?? '';
      if (_pendingAdminApproval) {
        // Don't change condition — submit revert request for admin approval
        final prefs = await SharedPreferences.getInstance();
        final actor = prefs.getString('user_name') ?? '';
        await DBHelper.instance.insertRevertRequest(
          instrumentCode: widget.instrument.instrumentCode,
          instrumentName: widget.instrument.instrumentName,
          requestedCondition: _condition,
          reason: _changeReason ?? '',
          requestedBy: actor,
        );
        if (mounted) {
          Navigator.pop(context);
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Revert request submitted — awaiting admin approval'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3)));
        }
        return;
      }
      await DBHelper.instance.updateInstrumentDetails(
        code: widget.instrument.instrumentCode,
        condition: _condition,
        conditionChangeReason: _changeReason,
        pendingAdminApproval: _pendingAdminApproval,
        location: _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        scheduledRepairDate: _repairDate?.toIso8601String().split('T').first,
        clearRepairDate:
            _repairDate == null && widget.instrument.scheduledRepairDate != null,
        scheduledCondemnDate:
            _condemnDate?.toIso8601String().split('T').first,
        clearCondemnDate:
            _condemnDate == null && widget.instrument.scheduledCondemnDate != null,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        clearNotes:
            _notesCtrl.text.trim().isEmpty && widget.instrument.notes != null,
      );
      if (_condition != widget.instrument.currentCondition) {
        final detail =
            '${widget.instrument.instrumentCode} (${widget.instrument.instrumentName}): '
            '${widget.instrument.currentCondition} → $_condition'
            '${_changeReason != null ? " — $_changeReason" : ""}';
        await DBHelper.instance.logActivity(
          eventType: 'condition_changed',
          eventDetail: detail,
          actor: actor,
        );
        await DBHelper.instance.logInstrumentEvent(
          instrumentCode: widget.instrument.instrumentCode,
          eventType: 'condition_changed',
          eventDetail: detail,
          actor: actor,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Instrument updated'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red));
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final inst = widget.instrument;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 16),
            Text(inst.instrumentName,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            Text(inst.instrumentCode,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 20),
            _sectionLabel('CONDITION'),
            // ── Calibration status display ─────────────────────────────────
            Builder(builder: (_) {
              final inst = widget.instrument;
              final days = inst.daysUntilCalibrationDue;
              final overdue = inst.isCalibrationOverdue;
              final lastDate = inst.lastCalibratedDate != null
                  ? inst.lastCalibratedDate!.substring(0, 10)
                  : 'Never';
              final statusText = overdue
                  ? 'OVERDUE'
                  : days != null && days <= 7
                      ? 'Due in $days days'
                      : days != null
                          ? 'Due in $days days'
                          : 'Never calibrated';
              final statusColor = overdue
                  ? Colors.red
                  : days != null && days <= 7
                      ? Colors.orange
                      : Colors.green;
              return GestureDetector(
                onTap: () => _showCalibrateDialog(),
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    Icon(Icons.science, color: statusColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last calibrated: $lastDate',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                          Text(statusText,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Icon(Icons.touch_app, color: statusColor.withValues(alpha: 0.6), size: 14),
                  ]),
                ),
              );
            }),
            if (_pendingAdminApproval)
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: const Row(children: [
                  Icon(Icons.hourglass_top, color: Colors.orange, size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Pending admin approval to revert from Condemning',
                        style: TextStyle(color: Colors.orange, fontSize: 11)),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Row(
                children: [
              ('Functioning', Colors.green, Icons.check_circle),
              ('For Repair', Colors.orange, Icons.build),
              ('Condemning', Colors.red, Icons.cancel),
            ].map((entry) {
              final (label, color, icon) = entry;
              final selected = _condition == label;
              return Expanded(
                  child: GestureDetector(
                onTap: () => _handleConditionTap(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.18)
                        : const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? color : const Color(0xFF1E3A5F),
                        width: selected ? 2 : 1),
                  ),
                  child: Column(children: [
                    Icon(icon,
                        color: selected ? color : Colors.white38, size: 18),
                    const SizedBox(height: 4),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: selected ? color : Colors.white54,
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ]),
                ),
              ));
            }).toList()),
            const SizedBox(height: 16),
            _sectionLabel('LOCATION'),
            const SizedBox(height: 8),
            _textField(_locationCtrl, 'e.g. Lab Room 3, Storage B', Icons.location_on),
            const SizedBox(height: 16),
            // Only show repair date when condition is For Repair
            if (_condition == 'For Repair') ...[
              _sectionLabel('SCHEDULED REPAIR DATE'),
              const SizedBox(height: 8),
              _datePicker(
                  label: _fmt(_repairDate),
                  icon: Icons.build,
                  color: Colors.orange,
                  onTap: () => _pickDate(isRepair: true),
                  onClear: _repairDate != null
                      ? () => setState(() => _repairDate = null)
                      : null),
              const SizedBox(height: 12),
            ],
            // Only show condemn date when condition is Condemning
            if (_condition == 'Condemning') ...[
              _sectionLabel('SCHEDULED CONDEMN DATE'),
              const SizedBox(height: 8),
              _datePicker(
                  label: _fmt(_condemnDate),
                  icon: Icons.cancel,
                  color: Colors.red,
                  onTap: () => _pickDate(isRepair: false),
                  onClear: _condemnDate != null
                      ? () => setState(() => _condemnDate = null)
                      : null),
              const SizedBox(height: 12),
            ],
            _sectionLabel('NOTES'),
            const SizedBox(height: 8),
            _textField(_notesCtrl, 'Any remarks about this instrument...', Icons.notes,
                maxLines: 3),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: _saving
                    ? const CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2)
                    : const Text('SAVE CHANGES',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Color(0xFFF5A623),
          fontSize: 10,
          letterSpacing: 3,
          fontWeight: FontWeight.bold));

  Widget _textField(TextEditingController ctrl, String hint, IconData icon,
          {int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: maxLines == 1 ? Icon(icon, color: const Color(0xFFF5A623)) : null,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFF5A623))),
          filled: true,
          fillColor: const Color(0xFF0D1B2A),
        ),
      );

  Widget _datePicker({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final isSet = label != 'Not set';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
            color: isSet ? color.withValues(alpha: 0.08) : const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSet ? color : const Color(0xFF1E3A5F))),
        child: Row(children: [
          Icon(icon, color: isSet ? color : Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: isSet ? color : Colors.white38,
                      fontSize: 14,
                      fontWeight: isSet ? FontWeight.bold : FontWeight.normal))),
          if (onClear != null)
            GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, color: Colors.white38, size: 18))
          else
            const Icon(Icons.calendar_today, color: Colors.white38, size: 16),
        ]),
      ),
    );
  }
}