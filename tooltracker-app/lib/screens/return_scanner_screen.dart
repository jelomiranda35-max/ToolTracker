// return_scanner_screen.dart — Build 15
//  ✅ Fix 2: After selecting "For Repair" or "Condemning" condition during return,
//     user is prompted to set the scheduled date for that condition.
//     The date is saved to the instrument's scheduledRepairDate / scheduledCondemnDate.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../models/dispatch.dart';

class ReturnScannerScreen extends StatefulWidget {
  final Dispatch dispatch;
  final List<DispatchItem> items;

  const ReturnScannerScreen({
    super.key,
    required this.dispatch,
    required this.items,
  });

  @override
  State<ReturnScannerScreen> createState() => _ReturnScannerScreenState();
}

class _ReturnScannerScreenState extends State<ReturnScannerScreen> {
  final Set<String> _scannedCodes = {};
  final Map<String, String> _returnConditions = {};

  // FIX 2: store scheduled dates set during return condition dialog
  final Map<String, DateTime> _scheduledRepairDates = {};
  final Map<String, DateTime> _scheduledCondemnDates = {};

  final List<String> _photoPaths = [];
  String? _processedByName;

  bool _scanning = false;
  bool _confirming = false;
  bool _torchOn = false;
  final MobileScannerController _controller = MobileScannerController();
  final ImagePicker _picker = ImagePicker();

  bool get _allScanned =>
      widget.items.every((i) => _scannedCodes.contains(i.instrumentCode));

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _processedByName = prefs.getString('user_name'));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanning) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null) return;

    if (_scannedCodes.contains(barcode)) {
      _showMsg('Already scanned', Colors.orange);
      return;
    }

    final match =
        widget.items.where((i) => i.instrumentCode == barcode).firstOrNull;

    if (match == null) {
      _showMsg('This instrument is not part of this dispatch', Colors.red);
      return;
    }

    setState(() => _scanning = true);
    _showConditionDialog(match);
  }

  // ── FIX 2: Condition dialog with optional date step ─────────────────────────

  void _showConditionDialog(DispatchItem item) {
    String selected = 'Functioning';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A5C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Declare Condition',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(height: 4),
              Text(item.instrumentName,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              Text(item.instrumentCode,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('What is the condition of this instrument?',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 14),
              ...[
                ('Functioning', Colors.green, Icons.check_circle),
                ('For Repair', Colors.orange, Icons.build),
                ('Condemning', Colors.red, Icons.cancel),
              ].map((entry) {
                final (label, color, icon) = entry;
                final isSelected = selected == label;
                return GestureDetector(
                  onTap: () => setDialogState(() => selected = label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.18)
                          : const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? color : const Color(0xFF1E3A5F),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(icon,
                          color: isSelected ? color : Colors.white38, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: TextStyle(
                                    color: isSelected ? color : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 14)),
                            // FIX 2: hint text for repair/condemn
                            if (label == 'For Repair' || label == 'Condemning')
                              Text(
                                'You will be asked to set a scheduled date',
                                style: TextStyle(
                                    color: color.withOpacity(0.6),
                                    fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);

                // FIX 2: If condition requires a date, show date picker before confirming
                if (selected == 'For Repair' || selected == 'Condemning') {
                  await _promptScheduledDate(
                    item: item,
                    condition: selected,
                  );
                } else {
                  // Functioning — confirm immediately
                  _confirmCondition(item: item, condition: selected);
                }
              },
              child: const Text('CONFIRM',
                  style: TextStyle(
                      color: Color(0xFFF5A623), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _scanning = false);
    });
  }

  // FIX 2: Show date picker after For Repair / Condemning is selected
  Future<void> _promptScheduledDate({
    required DispatchItem item,
    required String condition,
  }) async {
    final isRepair = condition == 'For Repair';
    final color = isRepair ? Colors.orange : Colors.red;
    final icon = isRepair ? Icons.build : Icons.cancel;
    final label = isRepair ? 'Scheduled Repair Date' : 'Scheduled Condemn Date';

    DateTime? pickedDate;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A5C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Text(item.instrumentName,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isRepair
                    ? 'When should this instrument go for repair?'
                    : 'When should this instrument be condemned?',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Date display / picker button
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: pickedDate ?? now.add(const Duration(days: 7)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365 * 3)),
                    builder: (c, child) => Theme(
                      data: ThemeData.dark().copyWith(
                          colorScheme: ColorScheme.dark(
                              primary: color,
                              onPrimary: Colors.white,
                              surface: const Color(0xFF1A3A5C))),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setDialogState(() => pickedDate = picked);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: pickedDate != null
                        ? color.withOpacity(0.1)
                        : const Color(0xFF0D1B2A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: pickedDate != null
                            ? color
                            : const Color(0xFF1E3A5F),
                        width: pickedDate != null ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        color: pickedDate != null ? color : Colors.white38,
                        size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pickedDate == null
                            ? 'Tap to set date'
                            : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                        style: TextStyle(
                            color: pickedDate != null ? color : Colors.white38,
                            fontSize: 15,
                            fontWeight: pickedDate != null
                                ? FontWeight.bold
                                : FontWeight.normal),
                      ),
                    ),
                    if (pickedDate != null)
                      Icon(Icons.check_circle, color: color, size: 18),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can also skip — the date can be set later from the Instruments tab.',
                style: TextStyle(color: Colors.white24, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Skip date — confirm condition without date
                _confirmCondition(item: item, condition: condition, scheduledDate: null);
              },
              child: const Text('SKIP DATE',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmCondition(
                    item: item, condition: condition, scheduledDate: pickedDate);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.white),
              child: const Text('CONFIRM',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // FIX 2: Confirm condition and store scheduled date if provided
  void _confirmCondition({
    required DispatchItem item,
    required String condition,
    DateTime? scheduledDate,
  }) {
    setState(() {
      _scannedCodes.add(item.instrumentCode);
      _returnConditions[item.instrumentCode] = condition;
      // Store scheduled dates to be saved after confirm return
      if (scheduledDate != null) {
        if (condition == 'For Repair') {
          _scheduledRepairDates[item.instrumentCode] = scheduledDate;
        } else if (condition == 'Condemning') {
          _scheduledCondemnDates[item.instrumentCode] = scheduledDate;
        }
      }
      _scanning = false;
    });

    final dateStr = scheduledDate != null
        ? '  ·  📅 ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year}'
        : '';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ ${item.instrumentName} — $condition$dateStr'),
      backgroundColor: condition == 'Functioning'
          ? Colors.green
          : condition == 'For Repair'
              ? Colors.orange
              : Colors.red,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (photo == null) return;
      setState(() => _photoPaths.add(photo.path));
    } catch (e) {
      _showMsg('Could not open camera: $e', Colors.red);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photoPaths.removeAt(index));
  }

  // FIX 2: After confirming return, save any scheduled dates to the DB
  Future<void> _confirmReturn() async {
    if (!_allScanned) return;
    setState(() => _confirming = true);

    try {
      final codes = widget.items.map((i) => i.instrumentCode).toList();
      final prefs2 = await SharedPreferences.getInstance();
      final returnActor = prefs2.getString('user_name') ?? '';
      await DBHelper.instance.logActivity(
        eventType: 'returned',
        eventDetail: 'Instruments returned for dispatch ${widget.dispatch.dispatchNo}',
        actor: returnActor,
      );
      await DBHelper.instance.returnDispatch(
        widget.dispatch.id!,
        codes,
        returnConditions: _returnConditions,
        photoPaths: _photoPaths.isNotEmpty ? _photoPaths : null,
        processedByName: _processedByName,
        dispatchNo: widget.dispatch.dispatchNo,
      );

      // FIX 2: Save scheduled dates for any instruments marked for repair/condemn
      for (final entry in _scheduledRepairDates.entries) {
        await DBHelper.instance.updateInstrumentDetails(
          code: entry.key,
          scheduledRepairDate: entry.value.toIso8601String().split('T').first,
        );
      }
      for (final entry in _scheduledCondemnDates.entries) {
        await DBHelper.instance.updateInstrumentDetails(
          code: entry.key,
          scheduledCondemnDate: entry.value.toIso8601String().split('T').first,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('All instruments returned successfully'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _confirming = false);
        _showMsg('Failed to confirm return. Please try again.', Colors.red);
      }
    }
  }

  void _showMsg(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final done = _scannedCodes.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Return Instruments',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            Text(widget.dispatch.dispatchNo,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
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
      body: Column(
        children: [
          // Progress bar
          Container(
            color: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$done / $total instruments scanned',
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                    Text(
                      _allScanned ? 'ALL DONE ✓' : 'Scan remaining...',
                      style: TextStyle(
                          color: _allScanned ? Colors.green : Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  backgroundColor: const Color(0xFF1E2D47),
                  color: _allScanned ? Colors.green : Colors.orange,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            ),
          ),

          // Camera
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _allScanned
                              ? Colors.green
                              : const Color(0xFF10B981),
                          width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _allScanned
                          ? 'All instruments scanned — confirm below'
                          : 'Scan each instrument barcode',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom panel
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF111827),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('INSTRUMENTS TO RETURN',
                          style: TextStyle(
                              color: Color(0xFF00D4FF),
                              fontSize: 10,
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: widget.items.length,
                      itemBuilder: (_, i) {
                        final item = widget.items[i];
                        final isDone = _scannedCodes.contains(item.instrumentCode);
                        final cond = _returnConditions[item.instrumentCode];
                        Color condColor = Colors.green;
                        if (cond == 'For Repair') condColor = Colors.orange;
                        if (cond == 'Condemning') condColor = Colors.red;

                        // FIX 2: show scheduled date badge if set
                        final repairDate = _scheduledRepairDates[item.instrumentCode];
                        final condemnDate = _scheduledCondemnDates[item.instrumentCode];
                        final scheduledDate = repairDate ?? condemnDate;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDone
                                ? condColor.withOpacity(0.07)
                                : const Color(0xFF0A0E1A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDone
                                  ? condColor.withOpacity(0.4)
                                  : const Color(0xFF1E2D47),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDone
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isDone ? condColor : Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.instrumentName,
                                        style: TextStyle(
                                            color: isDone ? condColor : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text(item.instrumentCode,
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 11)),
                                    // FIX 2: show scheduled date if set
                                    if (scheduledDate != null)
                                      Text(
                                        '📅 Scheduled: ${scheduledDate.day}/${scheduledDate.month}/${scheduledDate.year}',
                                        style: TextStyle(
                                            color: condColor, fontSize: 10),
                                      ),
                                  ],
                                ),
                              ),
                              if (isDone && cond != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: condColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(color: condColor),
                                  ),
                                  child: Text(cond,
                                      style: TextStyle(
                                          color: condColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Photo section
                  if (_allScanned) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('RETURN PHOTOS (OPTIONAL)',
                                style: TextStyle(
                                    color: Color(0xFFF5A623),
                                    fontSize: 10,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold)),
                          ),
                          TextButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.camera_alt,
                                color: Color(0xFFF5A623), size: 16),
                            label: const Text('Add Photo',
                                style: TextStyle(
                                    color: Color(0xFFF5A623), fontSize: 12)),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          ),
                        ],
                      ),
                    ),
                    if (_photoPaths.isNotEmpty)
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _photoPaths.length,
                          itemBuilder: (_, i) => Stack(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFF5A623)
                                          .withOpacity(0.4)),
                                  image: DecorationImage(
                                    image: FileImage(File(_photoPaths[i])),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () => _removePhoto(i),
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(left: 14, bottom: 6),
                        child: Text(
                          'No photos added — tap "Add Photo" to attach form images',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],

                  // Confirm button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (_allScanned && !_confirming)
                            ? _confirmReturn
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.green.withOpacity(0.25),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _confirming
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : Text(
                                _allScanned
                                    ? 'CONFIRM ALL RETURNED${_photoPaths.isNotEmpty ? ' (${_photoPaths.length} photo${_photoPaths.length > 1 ? 's' : ''})' : ''}'
                                    : 'Scan all instruments first (${total - done} remaining)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}