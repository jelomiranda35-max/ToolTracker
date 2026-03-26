import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/dispatch.dart';
import '../services/sync_service.dart';
import 'return_scanner_screen.dart';

class DispatchesListScreen extends StatefulWidget {
  const DispatchesListScreen({super.key});

  @override
  State<DispatchesListScreen> createState() => _DispatchesListScreenState();
}

class _DispatchesListScreenState extends State<DispatchesListScreen> {
  List<Dispatch> _dispatches = [];
  List<Dispatch> _filtered = [];
  bool _loading = true;

  // ── Date filter ──
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _expandedMonths = {};

  @override
  void initState() {
    super.initState();
    // Default: expand current month
    _expandedMonths.add(DateFormat('MMMM yyyy').format(DateTime.now()));
    _loadDispatches();
  }

  Future<void> _loadDispatches() async {
    setState(() => _loading = true);

    // Pull latest from server so dispatches from all devices are visible
    if (await SyncService.isConnected()) {
      await SyncService.instance.syncAll();
    }

    final dispatches = await DBHelper.instance.getAllDispatches();
    if (mounted) {
      setState(() {
        _dispatches = dispatches;
        _loading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final now = DateTime.now();
    final toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    setState(() {
      _filtered = _dispatches.where((d) {
        try {
          final dateOut = DateTime.parse(d.dateOut);
          return !dateOut.isBefore(_fromDate) && !dateOut.isAfter(toDate);
        } catch (_) {
          return true;
        }
      }).toList()
        ..sort((a, b) {
          try {
            return DateTime.parse(b.dateOut).compareTo(DateTime.parse(a.dateOut));
          } catch (_) {
            return 0;
          }
        });
    });
  }

  Map<String, List<Dispatch>> _groupByMonth(List<Dispatch> dispatches) {
    final Map<String, List<Dispatch>> groups = {};
    for (final d in dispatches) {
      String key;
      try {
        final date = DateTime.parse(d.dateOut);
        key = DateFormat('MMMM yyyy').format(date);
      } catch (_) {
        key = 'Unknown Date';
      }
      groups.putIfAbsent(key, () => []).add(d);
    }
    return groups;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00D4FF),
            surface: Color(0xFF111827),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _applyFilter();
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy  hh:mm a').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  void _showDispatchDetail(Dispatch dispatch) async {
    final items = await DBHelper.instance.getDispatchItems(dispatch.id!);
    if (!mounted) return;

    final isOut = dispatch.dateIn == null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
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
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(dispatch.dispatchNo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20)),
                  ),
                  _statusBadge(isOut ? 'Out' : 'Returned'),
                ],
              ),
              const SizedBox(height: 16),
              _detailRow(Icons.person, 'Test Engineer', dispatch.testEngineer),
              if (dispatch.processedByName != null &&
                  dispatch.processedByName!.isNotEmpty)
                _detailRow(
                    Icons.badge, 'Processed By', dispatch.processedByName!),
              _detailRow(
                  Icons.logout, 'Date Out', _formatDate(dispatch.dateOut)),
              _detailRow(
                  Icons.login, 'Date In', _formatDate(dispatch.dateIn)),
              if (dispatch.remarks != null && dispatch.remarks!.isNotEmpty)
                _detailRow(Icons.notes, 'Remarks', dispatch.remarks!),

              // Student info
              if (dispatch.isStudent) ...[
                const SizedBox(height: 8),
                _detailRow(
                    Icons.school, 'Student', dispatch.studentName ?? '—'),
                _detailRow(
                    Icons.badge, 'Student ID', dispatch.studentId ?? '—'),
              ],

              const SizedBox(height: 20),
              const Text('INSTRUMENTS',
                  style: TextStyle(
                      color: Color(0xFF00D4FF),
                      fontSize: 11,
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E2D47)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.build,
                            color: isOut
                                ? Colors.orange
                                : const Color(0xFF00D4FF),
                            size: 16),
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
                                      color: Colors.grey, fontSize: 11)),
                              if (item.returnCondition != null &&
                                  item.returnCondition!.isNotEmpty)
                                Text(
                                  'Returned: ${item.returnCondition}',
                                  style: TextStyle(
                                    color: item.returnCondition == 'Functioning'
                                        ? Colors.green
                                        : item.returnCondition == 'For Repair'
                                            ? Colors.orange
                                            : Colors.red,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),

              if (isOut) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final returned = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReturnScannerScreen(
                            dispatch: dispatch,
                            items: items,
                          ),
                        ),
                      );
                      if (returned == true) _loadDispatches();
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Return Instruments',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
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

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00D4FF), size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByMonth(_filtered);
    final groupKeys = groups.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title:
            const Text('Dispatches', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)),
            onPressed: _loadDispatches,
          )
        ],
      ),
      body: Column(
        children: [
          // ── From-date picker row ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF111827),
            child: Row(
              children: [
                const Icon(Icons.date_range, color: Color(0xFF00D4FF), size: 16),
                const SizedBox(width: 8),
                const Text('From:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickFromDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E2D47)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          DateFormat('MMM dd, yyyy').format(_fromDate),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_calendar, color: Color(0xFF00D4FF), size: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('To:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E2D47)),
                  ),
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(DateTime.now()),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // ── Count label ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtered.length} dispatch${_filtered.length != 1 ? 'es' : ''} · ${groupKeys.length} month${groupKeys.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ),
          // ── Body ──
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
                : RefreshIndicator(
                    onRefresh: _loadDispatches,
                    child: _filtered.isEmpty
                        ? const Center(
                            child: Text('No dispatches in this date range',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: groupKeys.length,
                            itemBuilder: (_, gi) {
                              final monthKey = groupKeys[gi];
                              final monthDispatches = groups[monthKey]!;
                              final isExpanded = _expandedMonths.contains(monthKey);
                              final outCount = monthDispatches.where((d) => d.dateIn == null).length;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111827),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF1E2D47)),
                                ),
                                child: Column(
                                  children: [
                                    // Month header
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setState(() {
                                          if (isExpanded) {
                                            _expandedMonths.remove(monthKey);
                                          } else {
                                            _expandedMonths.add(monthKey);
                                          }
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.folder_outlined, color: Color(0xFF00D4FF), size: 18),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(monthKey,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00D4FF).withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                '${monthDispatches.length}',
                                                style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            if (outCount > 0) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orange.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  '$outCount out',
                                                  style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 8),
                                            Icon(
                                              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                              color: const Color(0xFF00D4FF),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Expanded dispatch items
                                    if (isExpanded) ...[
                                      const Divider(color: Color(0xFF1E2D47), height: 1),
                                      ...monthDispatches.map((dispatch) {
                                        final isOut = dispatch.dateIn == null;
                                        return InkWell(
                                          onTap: () => _showDispatchDetail(dispatch),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Color(0xFF1E2D47), width: 0.5)),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 36,
                                                  height: 36,
                                                  decoration: BoxDecoration(
                                                    color: isOut
                                                        ? Colors.orange.withOpacity(0.12)
                                                        : Colors.green.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    isOut ? Icons.outbox : Icons.assignment_turned_in,
                                                    color: isOut ? Colors.orange : Colors.green,
                                                    size: 18,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(children: [
                                                        Expanded(
                                                          child: Text(dispatch.dispatchNo,
                                                              style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 13)),
                                                        ),
                                                        if (dispatch.isStudent)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.purple.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(color: Colors.purple.withOpacity(0.5)),
                                                            ),
                                                            child: const Text('STUDENT',
                                                                style: TextStyle(
                                                                    color: Colors.purple, fontSize: 9, fontWeight: FontWeight.bold)),
                                                          ),
                                                      ]),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        dispatch.isStudent
                                                            ? '${dispatch.studentName ?? dispatch.testEngineer} · ${dispatch.studentId ?? ''}'
                                                            : dispatch.testEngineer,
                                                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                                                      ),
                                                      Text(_formatDate(dispatch.dateOut),
                                                          style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                                    ],
                                                  ),
                                                ),
                                                _statusBadge(isOut ? 'Out' : 'Returned'),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}