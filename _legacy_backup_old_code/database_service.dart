import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // =====================================================
  // CREATE SUPER ADMIN PROFILE
  // =====================================================
  Future<void> saveSuperAdminProfile({
    required Map<String, dynamic> userProfile,
    required String collegeId,
    required String institutionName,
    required String uid,
  }) async {
    // 1. Save User Profile
    await _firestore.collection('users').doc(uid).set(userProfile);

    // 2. Initialize College Document
    await _firestore.collection('colleges').doc(collegeId).set({
      'collegeId': collegeId,
      'institutionName': institutionName,
      'initializedBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // =====================================================
  // CREATE SUB USER PROFILE
  // =====================================================
  Future<void> saveSubUserProfile({
    required String uid,
    required String fullName,
    required String email,
    required String role,
    required String parentCollegeId,
    required bool isActive,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'name': fullName,
      'email': email,
      'role': role,
      'collegeId': parentCollegeId,
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // =====================================================
  // GET USER PROFILE
  // =====================================================
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> doc = await _firestore
        .collection('users')
        .doc(uid)
        .get();

    if (doc.exists) {
      return doc.data();
    }
    return null;
  }
}
