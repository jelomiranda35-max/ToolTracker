class Dispatch {
  final int? id;
  final String dispatchNo;
  final String testEngineer;
  final int processedById;
  final String? processedByName;
  final String dateOut;
  final String? dateIn;
  final String? remarks;
  final String? returnPhotoPathsRaw; // comma-separated string from DB
  final int synced;
  final int conflict;

  // ── Borrower fields ───────────────────────────────────────────────────────
  final String dispatchType; // 'staff' | 'student'
  final String? studentName;   // kept for backward compat (borrower name)
  final String? studentId;     // kept for backward compat (borrower ID)
  final String? studentFormPhotoPath;
  final String? borrowerContact; // contact number
  final String? borrowerEmail;   // email address
  final String? borrowerPurpose; // purpose of borrowing

  Dispatch({
    this.id,
    required this.dispatchNo,
    required this.testEngineer,
    required this.processedById,
    this.processedByName,
    required this.dateOut,
    this.dateIn,
    this.remarks,
    this.returnPhotoPathsRaw,
    this.synced = 0,
    this.conflict = 0,
    this.dispatchType = 'staff',
    this.studentName,
    this.studentId,
    this.studentFormPhotoPath,
    this.borrowerContact,
    this.borrowerEmail,
    this.borrowerPurpose,
  });

  /// List of photo paths for return photos
  List<String> get returnPhotoPaths {
    if (returnPhotoPathsRaw == null || returnPhotoPathsRaw!.isEmpty) return [];
    return returnPhotoPathsRaw!.split(',').where((s) => s.isNotEmpty).toList();
  }

  /// Backward compat alias
  List<String> get returnPhotoPathsList => returnPhotoPaths;

  /// True when this is a student borrowing dispatch
  bool get isStudent =>
      dispatchType == 'student' || dispatchType == 'Student';

  factory Dispatch.fromMap(Map<String, dynamic> map) {
    return Dispatch(
      id: map['id'],
      dispatchNo: map['dispatch_no'] ?? '',
      testEngineer: map['test_engineer'] ?? '',
      processedById: map['processed_by_id'] ?? 0,
      processedByName: map['processed_by_name'],
      dateOut: map['date_out'] ?? '',
      dateIn: map['date_in'],
      remarks: map['remarks'],
      returnPhotoPathsRaw: map['return_photo_paths'],
      synced: map['synced'] ?? 0,
      conflict: map['conflict'] ?? 0,
      dispatchType: map['dispatch_type'] ?? 'staff',
      studentName: map['student_name'],
      studentId: map['student_id'],
      studentFormPhotoPath: map['student_form_photo_path'],
      borrowerContact: map['borrower_contact'],
      borrowerEmail: map['borrower_email'],
      borrowerPurpose: map['borrower_purpose'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dispatch_no': dispatchNo,
      'test_engineer': testEngineer,
      'processed_by_id': processedById,
      'processed_by_name': processedByName,
      'date_out': dateOut,
      'date_in': dateIn,
      'remarks': remarks,
      'return_photo_paths': returnPhotoPathsRaw,
      'synced': synced,
      'conflict': conflict,
      'dispatch_type': dispatchType,
      'student_name': studentName,
      'student_id': studentId,
      'student_form_photo_path': studentFormPhotoPath,
      'borrower_contact': borrowerContact,
      'borrower_email': borrowerEmail,
      'borrower_purpose': borrowerPurpose,
    };
  }
}

// ── DispatchItem ──────────────────────────────────────────────────────────────

class DispatchItem {
  final int? id;
  final int? dispatchId;
  final String instrumentCode;
  final String instrumentName;
  final String currentCondition;
  final String? returnCondition;
  final String? remarks;

  DispatchItem({
    this.id,
    this.dispatchId,
    required this.instrumentCode,
    required this.instrumentName,
    this.currentCondition = 'Functioning',
    this.returnCondition,
    this.remarks,
  });

  factory DispatchItem.fromMap(Map<String, dynamic> map) {
    return DispatchItem(
      id: map['id'],
      dispatchId: map['dispatch_id'],
      instrumentCode: map['instrument_code'] ?? '',
      instrumentName: map['instrument_name'] ?? '',
      currentCondition: map['current_condition'] ?? 'Functioning',
      returnCondition: map['return_condition'],
      remarks: map['remarks'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'instrument_code': instrumentCode,
      'instrument_name': instrumentName,
      'current_condition': currentCondition,
      'return_condition': returnCondition,
      'remarks': remarks,
    };
  }
}