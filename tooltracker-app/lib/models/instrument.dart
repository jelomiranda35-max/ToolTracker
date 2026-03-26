class Instrument {
  final int? id;
  final String instrumentCode;
  final String instrumentName;
  final String? serialNumber;
  final String currentCondition;
  final String status;
  final String? location;
  final String? lastTouchDate;
  final String? lastTouchBy;
  final String? lastUpdated;
  // ── NEW: scheduling fields ──────────────────────────────────────────────────
  final String? scheduledRepairDate;
  final String? scheduledCondemnDate;
  final String? notes;
  final String? lastCalibratedDate;
  final String? calibrationNotes;

  Instrument({
    this.id,
    required this.instrumentCode,
    required this.instrumentName,
    this.serialNumber,
    this.currentCondition = 'Functioning',
    this.status = 'Available',
    this.location,
    this.lastTouchDate,
    this.lastTouchBy,
    this.lastUpdated,
    this.scheduledRepairDate,
    this.scheduledCondemnDate,
    this.notes,
    this.lastCalibratedDate,
    this.calibrationNotes,
  });

  factory Instrument.fromMap(Map<String, dynamic> map) {
    return Instrument(
      id: map['id'],
      instrumentCode: map['instrument_code'] ?? '',
      instrumentName: map['instrument_name'] ?? '',
      serialNumber: map['serial_number'],
      currentCondition: map['current_condition'] ?? 'Functioning',
      status: map['status'] ?? 'Available',
      location: map['location'],
      lastTouchDate: map['last_touch_date'],
      lastTouchBy: map['last_touch_by'],
      lastUpdated: map['last_updated'],
      scheduledRepairDate: map['scheduled_repair_date'],
      scheduledCondemnDate: map['scheduled_condemn_date'],
      notes: map['notes'],
      lastCalibratedDate: map['last_calibrated_date'],
      calibrationNotes: map['calibration_notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'instrument_code': instrumentCode,
      'instrument_name': instrumentName,
      'serial_number': serialNumber,
      'current_condition': currentCondition,
      'status': status,
      'location': location,
      'last_touch_date': lastTouchDate,
      'last_touch_by': lastTouchBy,
      'last_updated': lastUpdated,
      'scheduled_repair_date': scheduledRepairDate,
      'scheduled_condemn_date': scheduledCondemnDate,
      'notes': notes,
      'last_calibrated_date': lastCalibratedDate,
      'calibration_notes': calibrationNotes,
    };
  }

  Instrument copyWith({
    String? currentCondition,
    String? status,
    String? location,
    String? lastTouchDate,
    String? lastTouchBy,
    String? scheduledRepairDate,
    bool clearRepairDate = false,
    String? scheduledCondemnDate,
    bool clearCondemnDate = false,
    String? notes,
    bool clearNotes = false,
    String? lastCalibratedDate,
    bool clearCalibratedDate = false,
    String? calibrationNotes,
    bool clearCalibrationNotes = false,
  }) {
    return Instrument(
      id: id,
      instrumentCode: instrumentCode,
      instrumentName: instrumentName,
      serialNumber: serialNumber,
      currentCondition: currentCondition ?? this.currentCondition,
      status: status ?? this.status,
      location: location ?? this.location,
      lastTouchDate: lastTouchDate ?? this.lastTouchDate,
      lastTouchBy: lastTouchBy ?? this.lastTouchBy,
      lastUpdated: lastUpdated,
      scheduledRepairDate:
          clearRepairDate ? null : (scheduledRepairDate ?? this.scheduledRepairDate),
      scheduledCondemnDate:
          clearCondemnDate ? null : (scheduledCondemnDate ?? this.scheduledCondemnDate),
      notes: clearNotes ? null : (notes ?? this.notes),
      lastCalibratedDate:
          clearCalibratedDate ? null : (lastCalibratedDate ?? this.lastCalibratedDate),
      calibrationNotes:
          clearCalibrationNotes ? null : (calibrationNotes ?? this.calibrationNotes),
    );
  }

  // ── Helper getters ──────────────────────────────────────────────────────────

  /// Days the instrument has been out (only meaningful when status == 'In Use')
  int get daysOut {
    if (lastTouchDate == null) return 0;
    try {
      return DateTime.now()
          .difference(DateTime.parse(lastTouchDate!))
          .inDays;
    } catch (_) {
      return 0;
    }
  }

  bool get isOverdue => status == 'In Use' && daysOut >= overdueThresholdDays;

  /// Global overdue threshold — updated at runtime from SharedPreferences.
  /// Default 7 days. Call Instrument.setOverdueThreshold() on app start.
  static int overdueThresholdDays = 7;

  static void setOverdueThreshold(int days) {
    overdueThresholdDays = days;
  }

  /// Days until scheduled repair (negative = past due)
  int? get daysUntilRepair {
    if (scheduledRepairDate == null) return null;
    try {
      return DateTime.parse(scheduledRepairDate!)
          .difference(DateTime.now())
          .inDays;
    } catch (_) {
      return null;
    }
  }

  /// Days until scheduled condemn
  int? get daysUntilCondemn {
    if (scheduledCondemnDate == null) return null;
    try {
      return DateTime.parse(scheduledCondemnDate!)
          .difference(DateTime.now())
          .inDays;
    } catch (_) {
      return null;
    }
  }

  /// True if either scheduled date is within [withinDays] days,
  /// OR if condition is 'For Repair'/'Condemning' with no date yet set.
  bool isUpcoming({int withinDays = 30}) {
    final r = daysUntilRepair;
    final c = daysUntilCondemn;
    if ((r != null && r <= withinDays) || (c != null && c <= withinDays)) {
      return true;
    }
    return currentCondition == 'For Repair' || currentCondition == 'Condemning';
  }

  /// True when condition is bad but no matching scheduled date has been set yet.
  /// Used by instruments_tab to show a "needs scheduling" prompt.
  bool get needsSchedule =>
      (currentCondition == 'For Repair' && scheduledRepairDate == null) ||
      (currentCondition == 'Condemning' && scheduledCondemnDate == null);

  // ── Calibration helpers ─────────────────────────────────────────────────────

  /// Days since last calibration (null if never calibrated)
  int? get daysSinceCalibration {
    if (lastCalibratedDate == null) return null;
    try {
      return DateTime.now()
          .difference(DateTime.parse(lastCalibratedDate!))
          .inDays;
    } catch (_) {
      return null;
    }
  }

  /// True when calibration is overdue (>365 days or never calibrated)
  bool get isCalibrationOverdue {
    final days = daysSinceCalibration;
    if (days == null) return true;
    return days > 365;
  }

  /// Days until calibration expires (negative = overdue)
  int? get daysUntilCalibrationDue {
    final days = daysSinceCalibration;
    if (days == null) return null;
    return 365 - days;
  }

  /// True when calibration expires within 7 days (show in Upcoming tab)
  bool get calibrationDueSoon {
    final d = daysUntilCalibrationDue;
    if (d == null) return false;
    return d <= 7;
  }
}