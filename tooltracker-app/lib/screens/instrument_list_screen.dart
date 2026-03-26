import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/instrument.dart';

class InstrumentListScreen extends StatefulWidget {
  const InstrumentListScreen({super.key});

  @override
  State<InstrumentListScreen> createState() => _InstrumentListScreenState();
}

class _InstrumentListScreenState extends State<InstrumentListScreen> {
  List<Instrument> _instruments = [];
  List<Instrument> _filtered = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  Future<void> _loadInstruments() async {
    final instruments = await DBHelper.instance.getAllInstruments();
    setState(() {
      _instruments = instruments;
      _filtered = instruments;
    });
  }

  void _search(String query) {
    setState(() {
      _filtered = _instruments
          .where((i) =>
              i.instrumentName.toLowerCase().contains(query.toLowerCase()) ||
              i.instrumentCode.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Available':
        return Colors.green;
      case 'In Use':
        return Colors.orange;
      case 'For Repair':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Instruments',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search instruments...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon:
                    const Icon(Icons.search, color: Color(0xFF00D4FF)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E2D47)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00D4FF)),
                ),
                filled: true,
                fillColor: const Color(0xFF111827),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No instruments found',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final instrument = _filtered[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E2D47)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.build_circle,
                                color: Color(0xFF00D4FF), size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(instrument.instrumentName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text(instrument.instrumentCode,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(instrument.currentCondition,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(instrument.status)
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color: _statusColor(instrument.status)),
                              ),
                              child: Text(instrument.status,
                                  style: TextStyle(
                                      color: _statusColor(instrument.status),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
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
}