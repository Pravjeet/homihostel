import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added Firestore import

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Initialize Firestore

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
      // 1. Create Auth Account
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Failed to create user account.");
      }

      // 2. Generate College ID
      String cleanName = institutionName
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toLowerCase();

      String generatedCollegeId =
          'col_${cleanName}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      // 3. Prepare Profile Data Map
      Map<String, dynamic> userProfile = {
        'uid': firebaseUser.uid,
        'name': adminName,
        'email': email,
        'role': 'SuperAdmin',
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'isActive': true,
        'createdAt':
            FieldValue.serverTimestamp(), // Matches the gold standard test
      };

      // 4. WRITE TO FIRESTORE (Directly like the test)
      // Using .doc(uid).set() instead of .add() to link Auth and Firestore
      await _firestore
          .collection('users')
          .doc(firebaseUser.uid)
          .set(userProfile);

      // Optional: You might also want to save the college document directly here
      await _firestore.collection('colleges').doc(generatedCollegeId).set({
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'adminUid': firebaseUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return userProfile;
    } on FirebaseAuthException catch (e) {
      print("🚨 AUTH ERROR: ${e.message}");
      throw Exception(e.message ?? 'Failed to register institution.');
    } catch (e) {
      print("🚨 FIRESTORE DENIED IT: $e");
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

      // Fetch profile directly from Firestore
      DocumentSnapshot<Map<String, dynamic>> userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists || userDoc.data() == null) {
        throw Exception("User profile does not exist in Firestore.");
      }

      return userDoc.data();
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

      // Fetch profile directly from Firestore
      DocumentSnapshot<Map<String, dynamic>> userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      return userDoc.data();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // REGISTER SUB USER (FIXED FOR SESSION HIJACKING)
  // =====================================================
  Future<void> registerSubUser({
    required String fullName,
    required String email,
    required String role,
    required String password,
    required String parentCollegeId,
    required bool isActive,
  }) async {
    FirebaseApp? tempApp;
    try {
      // 1. Initialize temporary Firebase app
      tempApp = await Firebase.initializeApp(
        name: 'tempSubUserCreationApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      // 2. Create the user using the temporary Auth instance
      UserCredential userCredential = await FirebaseAuth.instanceFor(
        app: tempApp,
      ).createUserWithEmailAndPassword(email: email, password: password);

      User? newFirebaseUser = userCredential.user;

      if (newFirebaseUser != null) {
        // 3. WRITE TO FIRESTORE (Directly like the test)
        await _firestore.collection('users').doc(newFirebaseUser.uid).set({
          'uid': newFirebaseUser.uid,
          'name': fullName,
          'email': email,
          'role': role,
          'collegeId': parentCollegeId,
          'isActive': isActive,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      print("🚨 SUB-USER AUTH ERROR: ${e.message}");
      throw Exception(e.message ?? 'Failed to create sub-user account.');
    } catch (e) {
      print("🚨 SUB-USER FIRESTORE ERROR: $e");
      throw Exception(e.toString());
    } finally {
      // 4. Delete temp app
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  // =====================================================
  // GET COLLEGE ID OF CURRENT USER
  // =====================================================
  Future<String?> getCurrentCollegeId() async {
    try {
      Map<String, dynamic>? userProfile = await getCurrentUserProfile();
      if (userProfile == null) return null;

      return userProfile['collegeId'];
    } catch (_) {
      return null;
    }
  }

  // =====================================================
  // LOGOUT & STATE HELPERS
  // =====================================================
  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
