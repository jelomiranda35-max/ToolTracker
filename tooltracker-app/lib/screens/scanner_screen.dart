import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../database/db_helper.dart';
import '../models/instrument.dart';

enum ScannerMode { borrow, returnInstrument }

class ScannerScreen extends StatefulWidget {
  final ScannerMode mode;
  const ScannerScreen({super.key, required this.mode});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _scanned = false;
  bool _torchOn = false;
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null) return;
    setState(() => _scanned = true);

    final instrument = await DBHelper.instance.getInstrumentByCode(barcode);

    if (!mounted) return;

    if (instrument == null) {
      _showDialog(
        title: 'Not Found',
        content: 'No instrument found with code:\n$barcode',
        isError: true,
        onRetry: () => setState(() => _scanned = false),
      );
      return;
    }

    // BORROW MODE
    if (widget.mode == ScannerMode.borrow) {
      if (instrument.status != 'Available') {
        _showDialog(
          title: 'Not Available',
          content:
              '${instrument.instrumentName} is currently ${instrument.status}.\n\nScan a different instrument.',
          isError: true,
          onRetry: () => setState(() => _scanned = false),
        );
        return;
      }
      _showBorrowConfirm(instrument);
      return;
    }

    // RETURN MODE
    if (widget.mode == ScannerMode.returnInstrument) {
      if (instrument.status == 'Available') {
        _showDialog(
          title: 'Already Available',
          content:
              '${instrument.instrumentName} is already marked as Available.\n\nNothing to return.',
          isError: true,
          onRetry: () => setState(() => _scanned = false),
        );
        return;
      }
      _showReturnConfirm(instrument);
      return;
    }
  }

  void _showBorrowConfirm(Instrument instrument) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Instrument Found',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Name', instrument.instrumentName),
            _infoRow('Code', instrument.instrumentCode),
            _infoRow('Condition', instrument.currentCondition),
            _infoRow('Status', instrument.status),
            const SizedBox(height: 8),
            const Text('Add this instrument to the dispatch?',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _scanned = false);
            },
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, instrument);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D4FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Add to Dispatch',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showReturnConfirm(Instrument instrument) async {
    final dispatches = await DBHelper.instance.getAllDispatches();
    final activeDispatch = dispatches.where((d) => d.dateIn == null).firstOrNull;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Return Instrument',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Name', instrument.instrumentName),
            _infoRow('Code', instrument.instrumentCode),
            _infoRow('Status', instrument.status),
            if (activeDispatch != null)
              _infoRow('Dispatch', activeDispatch.dispatchNo),
            const SizedBox(height: 8),
            const Text('Confirm return of this instrument?',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _scanned = false);
            },
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (activeDispatch?.id != null) {
                await DBHelper.instance.returnDispatch(
                    activeDispatch!.id!, [instrument.instrumentCode]);
              } else {
                await DBHelper.instance
                    .updateInstrumentStatus(instrument.instrumentCode, 'Available');
              }
              if (mounted) {
                Navigator.pop(context);
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          '${instrument.instrumentName} returned successfully'),
                      backgroundColor: Colors.green),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Return',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDialog({
    required String title,
    required String content,
    required bool isError,
    required VoidCallback onRetry,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Text(title,
            style: TextStyle(
                color: isError ? Colors.redAccent : Colors.white)),
        content: Text(content,
            style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: const Text('Try Again',
                style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Go Back',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text('$label:',
                style:
                    const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBorrow = widget.mode == ScannerMode.borrow;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: Text(
          isBorrow ? 'Scan to Borrow' : 'Scan to Return',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
              color: _torchOn ? const Color(0xFFF5A623) : Colors.white54,
            ),
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                    color: isBorrow
                        ? const Color(0xFF00D4FF)
                        : const Color(0xFF10B981),
                    width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(32),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isBorrow
                    ? 'Point at instrument barcode to borrow'
                    : 'Point at instrument barcode to return',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}