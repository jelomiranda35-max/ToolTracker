import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../models/dispatch.dart';
import '../models/instrument.dart';
import '../services/api_service.dart';
import 'scanner_screen.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  final _dispatchNoController = TextEditingController();
  final _engineerController = TextEditingController();
  final _processedByController = TextEditingController();
  final _remarksController = TextEditingController();

  List<DispatchItem> _scannedItems = [];
  bool _loading = false;
  String _selectedCondition = 'Functioning';

  @override
  void initState() {
    super.initState();
    _prefillProcessedBy();
  }

  Future<void> _prefillProcessedBy() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    if (mounted) {
      setState(() => _processedByController.text = name);
    }
  }

  void _openScanner() async {
    final instrument = await Navigator.push<Instrument>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(mode: ScannerMode.borrow),
      ),
    );

    if (instrument == null) return;

    if (_scannedItems.any((i) => i.instrumentCode == instrument.instrumentCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${instrument.instrumentName} already added'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _scannedItems.add(DispatchItem(
        instrumentCode: instrument.instrumentCode,
        instrumentName: instrument.instrumentName,
        currentCondition: _selectedCondition,
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${instrument.instrumentName} added'),
          backgroundColor: Colors.green),
    );
  }

  Future<void> _submitDispatch() async {
    // ── Validation (all fields except Remarks are required) ──
    if (_dispatchNoController.text.trim().isEmpty) {
      _showError('Please enter a Dispatch No.');
      return;
    }
    if (_engineerController.text.trim().isEmpty) {
      _showError('Please enter the Test Engineer name.');
      return;
    }
    if (_processedByController.text.trim().isEmpty) {
      _showError('Please enter who is processing this dispatch.');
      return;
    }
    if (_scannedItems.isEmpty) {
      _showError('Please scan at least one instrument.');
      return;
    }

    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 1;

      final dispatch = Dispatch(
        dispatchNo: _dispatchNoController.text.trim(),
        testEngineer: _engineerController.text.trim(),
        processedById: userId,
        processedByName: _processedByController.text.trim(),
        dateOut: DateTime.now().toIso8601String(),
        remarks: _remarksController.text.trim(),
      );

      await DBHelper.instance.insertDispatch(dispatch, _scannedItems);
      final actor = _processedByController.text.trim();
      final detail = 'Dispatch ${dispatch.dispatchNo} — ${_scannedItems.length} instrument(s)';
      await DBHelper.instance.logActivity(
        eventType: 'dispatch_created',
        eventDetail: detail,
        actor: actor,
      );
      for (final item in _scannedItems) {
        await DBHelper.instance.logInstrumentEvent(
          instrumentCode: item.instrumentCode,
          eventType: 'dispatch_created',
          eventDetail: 'Dispatched in ${dispatch.dispatchNo} by $actor',
          actor: actor,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Dispatch created successfully'),
              backgroundColor: Colors.green),
        );
        
        // Sync to Google Sheets
        ApiService.pushToSheets('dispatch_created', {
          'dispatch_no': dispatch.dispatchNo,
          'test_engineer': dispatch.testEngineer,
          'date_out': dispatch.dateOut,
          'instruments': _scannedItems.map((i) => i.instrumentCode).toList(),
          'processed_by': _processedByController.text.trim(),
        });
        
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Failed to create dispatch.';
        if (e.toString().contains('UNIQUE') ||
            e.toString().contains('unique') ||
            e.toString().contains('duplicate')) {
          errorMsg =
              'Dispatch No. already exists. Please use a different number.';
        }
        _showError(errorMsg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('New Dispatch',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('DISPATCH INFO'),
            const SizedBox(height: 12),
            _field(_dispatchNoController, 'Dispatch No.', Icons.tag),
            const SizedBox(height: 12),
            _field(_engineerController, 'Test Engineer', Icons.engineering),
            const SizedBox(height: 12),
            _field(_processedByController, 'Processed By', Icons.person),
            const SizedBox(height: 12),
            _field(_remarksController, 'Remarks (optional)', Icons.notes),
            const SizedBox(height: 24),
            _sectionLabel('CONDITION OF INSTRUMENTS'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCondition,
              dropdownColor: const Color(0xFF111827),
              style: const TextStyle(color: Colors.white),
              decoration:
                  _inputDecoration('Condition', Icons.health_and_safety),
              items: ['Functioning', 'For Repair', 'Condemning']
                  .map((c) =>
                      DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCondition = v!),
            ),
            const SizedBox(height: 24),
            _sectionLabel('SCANNED INSTRUMENTS'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner,
                    color: Color(0xFF00D4FF)),
                label: const Text('Scan Instrument',
                    style: TextStyle(color: Color(0xFF00D4FF))),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF00D4FF)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_scannedItems.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No instruments scanned yet',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ..._scannedItems.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF00D4FF).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF00D4FF), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.instrumentName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${item.instrumentCode} · ${item.currentCondition}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.red, size: 20),
                          onPressed: () =>
                              setState(() => _scannedItems.remove(item)),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submitDispatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('CREATE DISPATCH',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Color(0xFF00D4FF),
          fontSize: 11,
          letterSpacing: 3,
          fontWeight: FontWeight.bold));

  Widget _field(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: const Color(0xFF00D4FF)),
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
    );
  }
}