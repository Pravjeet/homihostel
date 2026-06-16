import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // =====================================================
  // REGISTER SUPER ADMIN
  // =====================================================
  Future<Map<String, dynamic>?> registerSuperAdmin({
    required String institutionName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Failed to create user account.");
      }

      String cleanName = institutionName
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toLowerCase();

      String generatedCollegeId =
          'col_${cleanName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      Map<String, dynamic> userProfile = {
        'uid': firebaseUser.uid,
        'name': adminName,
        'email': email,
        'role': 'SuperAdmin',
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .set(userProfile);

      await _firestore.collection('colleges').doc(generatedCollegeId).set({
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'initializedBy': firebaseUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return userProfile;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Failed to register institution.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // LOGIN USER
  // =====================================================
  Future<Map<String, dynamic>?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = credential.user;

      if (user == null) {
        throw Exception("User authentication failed.");
      }

      DocumentSnapshot<Map<String, dynamic>> doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        throw Exception("User profile does not exist in Firestore.");
      }

      return doc.data();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Authentication failed.");
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // GET CURRENT USER PROFILE
  // =====================================================
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      User? user = _auth.currentUser;

      if (user == null) return null;

      DocumentSnapshot<Map<String, dynamic>> doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return null;

      return doc.data();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // REGISTER SUB USER
  // =====================================================
  Future<UserCredential?> registerSubUser({
    required String fullName,
    required String email,
    required String role,
    required String password,
    required String parentCollegeId,
    required bool isActive,
  }) async {
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        await _firestore.collection('users').doc(firebaseUser.uid).set({
          'uid': firebaseUser.uid,
          'name': fullName,
          'email': email,
          'role': role,
          'collegeId': parentCollegeId,
          'isActive': isActive,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Failed to create sub-user account.');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // GET COLLEGE ID OF CURRENT USER
  // =====================================================
  Future<String?> getCurrentCollegeId() async {
    try {
      User? user = _auth.currentUser;

      if (user == null) return null;

      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return null;

      return doc['collegeId'];
    } catch (_) {
      return null;
    }
  }

  // =====================================================
  // LOGOUT
  // =====================================================
  Future<void> logout() async {
    await _auth.signOut();
  }

  // =====================================================
  // CURRENT FIREBASE USER
  // =====================================================
  User? get currentUser => _auth.currentUser;

  // =====================================================
  // AUTH STATE CHANGES
  // =====================================================
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
