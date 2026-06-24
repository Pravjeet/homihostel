import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // =====================================================
  // REGISTER SUPER ADMIN (AND PROVISION WORKSPACE)
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
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 4. WRITE TO FIRESTORE USING ATOMIC BATCH
      WriteBatch batch = _firestore.batch();

      // A. Save User Profile
      DocumentReference userRef = _firestore
          .collection('users')
          .doc(firebaseUser.uid);
      batch.set(userRef, userProfile);

      // B. Save College Document
      DocumentReference collegeRef = _firestore
          .collection('colleges')
          .doc(generatedCollegeId);
      batch.set(collegeRef, {
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'adminUid': firebaseUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // C. Provision Default Role Permissions for this College
      Map<String, Map<String, dynamic>> defaultPermissions = {
        'Chief Warden': {
          'read': true,
          'get': true,
          'list': true,
          'write': true,
          'create': true,
          'update': true,
          'delete': true,
        },
        'Warden': {
          'read': true,
          'get': true,
          'list': true,
          'write': false,
          'create': true,
          'update': true,
          'delete': false,
        },
        'Student': {
          'read': false,
          'get': true,
          'list': false,
          'write': false,
          'create': false,
          'update': true,
          'delete': false,
        },
      };

      for (var role in defaultPermissions.entries) {
        DocumentReference permRef = collegeRef
            .collection('role_permissions')
            .doc(role.key);
        // Add timestamp to the permission map before saving
        Map<String, dynamic> permData = Map.from(role.value);
        permData['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(permRef, permData);
      }

      // Commit the entire workspace setup at once
      await batch.commit();

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
  // REGISTER SUB USER (WITH PRESERVED SESSION ISOLATION)
  // =====================================================
  Future<void> registerSubUser({
    required String fullName,
    required String email,
    required String password,
    required String parentCollegeId,
    required bool isActive,
    String? role, // Optional/nullable role assignment
  }) async {
    FirebaseApp? tempApp;
    try {
      // 1. Initialize temporary Firebase app to prevent session hijack
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
        // 3. WRITE TO FIRESTORE with injected college ID context
        await _firestore.collection('users').doc(newFirebaseUser.uid).set({
          'uid': newFirebaseUser.uid,
          'name': fullName,
          'email': email,
          'role': role ?? 'Student', // Fallback to Student if no role provided
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
      // 4. Clean up temp app context
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  // =====================================================
  // FETCH USERS SHARED UNDER THE SAME COLLEGE ID
  // =====================================================
  Future<List<Map<String, dynamic>>> getUsersByCollegeId(
    String collegeId,
  ) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('users')
          .where('collegeId', isEqualTo: collegeId)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print("🚨 FETCH USERS ERROR: $e");
      throw Exception('Failed to load institution users.');
    }
  }

  // =====================================================
  // UPDATE USER ROLE
  // =====================================================
  Future<void> updateUserRole({
    required String uid,
    required String? newRole,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).update({'role': newRole});
    } catch (e) {
      print("🚨 UPDATE ROLE ERROR: $e");
      throw Exception('Failed to update user role.');
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
