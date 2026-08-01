import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed wrapper around the `users/{uid}` document.
///
/// Using a model instead of `Map<String, dynamic>` everywhere means a typo in
/// a field name becomes a compile error rather than a silent `null` at runtime.
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String collegeId;

  /// Document id inside `colleges/{collegeId}/roles`. Null = not yet assigned.
  final String? roleId;

  /// Denormalised human-readable role name, so lists render without an extra read.
  final String? roleName;

  final bool isSuperAdmin;
  final bool isActive;
  final String? phone;
  final String? gender;
  final String? enrollmentNo;
  final DateTime? createdAt;

  // --- Optional profile detail ---
  //
  // None of this is asked for at account creation — you only need a name,
  // email and role to get someone in. These are filled in afterwards from the
  // user's detail screen, which is why every one of them is nullable.
  final String? course;
  final String? year;
  final String? dateOfBirth;
  final String? bloodGroup;
  final String? address;
  final String? guardianName;
  final String? guardianPhone;
  final String? guardianRelation;
  final String? notes;

  // --- Room allotment (denormalised from the room document) ---
  //
  // The room also stores this student's uid in `occupantUids`. Both sides are
  // written inside one transaction, so they can't disagree. The duplication
  // buys the student's "My Room" page a single document read instead of a
  // collection-group query across every room in the institution.
  final String? hostelId;
  final String? hostelName;
  final String? roomId;
  final String? roomNumber;
  final DateTime? allottedAt;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.collegeId,
    this.roleId,
    this.roleName,
    this.isSuperAdmin = false,
    this.isActive = true,
    this.phone,
    this.gender,
    this.enrollmentNo,
    this.createdAt,
    this.course,
    this.year,
    this.dateOfBirth,
    this.bloodGroup,
    this.address,
    this.guardianName,
    this.guardianPhone,
    this.guardianRelation,
    this.notes,
    this.hostelId,
    this.hostelName,
    this.roomId,
    this.roomNumber,
    this.allottedAt,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> m) {
    return AppUser(
      uid: uid,
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? m['name'] as String
          : 'Unnamed',
      email: m['email'] as String? ?? '',
      collegeId: m['collegeId'] as String? ?? '',
      roleId: m['roleId'] as String?,
      roleName: m['roleName'] as String?,
      isSuperAdmin: m['isSuperAdmin'] as bool? ?? false,
      isActive: m['isActive'] as bool? ?? true,
      phone: m['phone'] as String?,
      gender: m['gender'] as String?,
      enrollmentNo: m['enrollmentNo'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      course: m['course'] as String?,
      year: m['year'] as String?,
      dateOfBirth: m['dateOfBirth'] as String?,
      bloodGroup: m['bloodGroup'] as String?,
      address: m['address'] as String?,
      guardianName: m['guardianName'] as String?,
      guardianPhone: m['guardianPhone'] as String?,
      guardianRelation: m['guardianRelation'] as String?,
      notes: m['notes'] as String?,
      hostelId: m['hostelId'] as String?,
      hostelName: m['hostelName'] as String?,
      roomId: m['roomId'] as String?,
      roomNumber: m['roomNumber'] as String?,
      allottedAt: (m['allottedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'collegeId': collegeId,
    'roleId': roleId,
    'roleName': roleName,
    'isSuperAdmin': isSuperAdmin,
    'isActive': isActive,
    'phone': phone,
    'gender': gender,
    'enrollmentNo': enrollmentNo,
    'course': course,
    'year': year,
    'dateOfBirth': dateOfBirth,
    'bloodGroup': bloodGroup,
    'address': address,
    'guardianName': guardianName,
    'guardianPhone': guardianPhone,
    'guardianRelation': guardianRelation,
    'notes': notes,
    'hostelId': hostelId,
    'hostelName': hostelName,
    'roomId': roomId,
    'roomNumber': roomNumber,
  };

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get displayRole =>
      isSuperAdmin ? 'Super Admin' : (roleName ?? 'Unassigned');

  bool get isAllotted => roomId != null && hostelId != null;

  /// "Block A · Room 101", or null when not allotted.
  String? get roomLabel =>
      isAllotted ? '$hostelName · Room $roomNumber' : null;
}
