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
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);
      User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Failed to create user account.");
      }

      // Update display name in Firebase Auth
      await firebaseUser.updateDisplayName(adminName);
      await firebaseUser.reload();

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
        'gender': null,
        'phoneNumber': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      WriteBatch batch = _firestore.batch();

      DocumentReference userRef = _firestore
          .collection('users')
          .doc(firebaseUser.uid);
      batch.set(userRef, userProfile);

      DocumentReference collegeRef = _firestore
          .collection('colleges')
          .doc(generatedCollegeId);
      batch.set(collegeRef, {
        'collegeId': generatedCollegeId,
        'institutionName': institutionName,
        'adminUid': firebaseUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create ONLY SuperAdmin role (no default roles)
      DocumentReference roleRef = collegeRef
          .collection('role_permissions')
          .doc('SuperAdmin');
      batch.set(roleRef, {
        'read': true,
        'get': true,
        'list': true,
        'write': true,
        'create': true,
        'update': true,
        'delete': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      // Return updated user with fresh data
      return await getUserProfile(firebaseUser.uid);
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

      return await getUserProfile(user.uid);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Authentication failed.");
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // GET USER PROFILE BY UID
  // =====================================================
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> userDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get();
      if (!userDoc.exists || userDoc.data() == null) {
        return null;
      }

      return userDoc.data();
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

      return await getUserProfile(user.uid);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // =====================================================
  // GET AVAILABLE ROLES (Excludes SuperAdmin)
  // =====================================================
  Future<List<String>> getAvailableRoles(String collegeId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .get();
      List<String> roles = [];
      for (var doc in snapshot.docs) {
        // Exclude SuperAdmin from available roles
        if (doc.id != 'SuperAdmin') {
          roles.add(doc.id);
        }
      }
      return roles;
    } catch (e) {
      print("🚨 GET AVAILABLE ROLES ERROR: $e");
      return [];
    }
  }

  // =====================================================
  // CHECK IF ROLES EXIST (Excluding SuperAdmin)
  // =====================================================
  Future<bool> hasAvailableRoles(String collegeId) async {
    try {
      final roles = await getAvailableRoles(collegeId);
      return roles.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // =====================================================
  // REGISTER SUB USER (WITH PRESERVED SESSION ISOLATION)
  // =====================================================
  Future<Map<String, dynamic>> registerSubUser({
    required String fullName,
    required String email,
    required String password,
    required String parentCollegeId,
    required String role,
    String? gender,
    String? phoneNumber,
  }) async {
    // Validate that the role exists and is not SuperAdmin
    if (role == 'SuperAdmin') {
      throw Exception('Cannot assign SuperAdmin role to sub-users.');
    }

    final availableRoles = await getAvailableRoles(parentCollegeId);
    if (!availableRoles.contains(role)) {
      throw Exception(
        'Selected role "$role" does not exist. Please create it first.',
      );
    }

    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'tempSubUserCreationApp_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      UserCredential userCredential = await FirebaseAuth.instanceFor(
        app: tempApp,
      ).createUserWithEmailAndPassword(email: email, password: password);
      User? newFirebaseUser = userCredential.user;

      if (newFirebaseUser == null) {
        throw Exception("Failed to create user account.");
      }

      // Update display name in Firebase Auth
      await newFirebaseUser.updateDisplayName(fullName);
      await newFirebaseUser.reload();

      // Prepare user data with all fields
      Map<String, dynamic> userData = {
        'uid': newFirebaseUser.uid,
        'name': fullName,
        'email': email,
        'role': role,
        'collegeId': parentCollegeId,
        'gender': gender,
        'phoneNumber': phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Store user in Firestore
      await _firestore
          .collection('users')
          .doc(newFirebaseUser.uid)
          .set(userData);
      return userData;
    } on FirebaseAuthException catch (e) {
      print("🚨 SUB-USER AUTH ERROR: ${e.message}");
      throw Exception(e.message ?? 'Failed to create sub-user account.');
    } catch (e) {
      print("🚨 SUB-USER FIRESTORE ERROR: $e");
      throw Exception(e.toString());
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  // =====================================================
  // UPDATE USER PROFILE (WITH ALL FIELDS - STANDARD)
  // =====================================================
  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? email,
    String? role,
    String? gender,
    String? phoneNumber,
  }) async {
    try {
      Map<String, dynamic> updateData = {};
      if (name != null) {
        updateData['name'] = name;
        // Update Firebase Auth display name
        User? user = _auth.currentUser;
        if (user != null && user.uid == uid) {
          await user.updateDisplayName(name);
          await user.reload();
        }
      }

      if (email != null) updateData['email'] = email;
      if (role != null) updateData['role'] = role;
      if (gender != null) updateData['gender'] = gender;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(uid).update(updateData);
    } catch (e) {
      print("🚨 UPDATE PROFILE ERROR: $e");
      throw Exception('Failed to update user profile.');
    }
  }

  // =====================================================
  // UPDATE ALL USER DETAILS (Including Dynamic Custom Data)
  // =====================================================
  Future<void> updateUserDetails(String uid, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = FieldValue.serverTimestamp();

      // If name is being updated, we also need to update Firebase Auth display name
      if (data.containsKey('name')) {
        User? user = _auth.currentUser;
        if (user != null && user.uid == uid) {
          await user.updateDisplayName(data['name']);
          await user.reload();
        }
      }

      await _firestore.collection('users').doc(uid).update(data);
    } catch (e) {
      print("🚨 UPDATE DETAILS ERROR: $e");
      throw Exception('Failed to update user details.');
    }
  }

  // =====================================================
  // USER MANAGEMENT
  // =====================================================

  // Update user role
  Future<void> updateUserRole({
    required String uid,
    required String? newRole,
  }) async {
    try {
      // Prevent assigning SuperAdmin role
      if (newRole == 'SuperAdmin') {
        throw Exception('Cannot assign SuperAdmin role to users.');
      }

      await _firestore.collection('users').doc(uid).update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("🚨 UPDATE ROLE ERROR: $e");
      throw Exception('Failed to update user role.');
    }
  }

  // Delete user
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
      print("🚨 DELETE USER ERROR: $e");
      throw Exception('Failed to delete user.');
    }
  }

  // Fetch users by college ID
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

  // Get user statistics
  Future<Map<String, int>> getUserStatistics(String collegeId) async {
    try {
      final users = await getUsersByCollegeId(collegeId);
      int total = 0;
      int students = 0;
      int wardens = 0;
      int chiefWardens = 0;
      for (var user in users) {
        if (user['role'] == 'SuperAdmin') continue;

        total++;
        final role = user['role'] ?? 'Unassigned';
        if (role == 'Student') {
          students++;
        } else if (role == 'Warden') {
          wardens++;
        } else if (role == 'Chief Warden') {
          chiefWardens++;
        }
      }

      return {
        'total': total,
        'students': students,
        'wardens': wardens,
        'chiefWardens': chiefWardens,
      };
    } catch (e) {
      print("🚨 STATISTICS ERROR: $e");
      return {'total': 0, 'students': 0, 'wardens': 0, 'chiefWardens': 0};
    }
  }

  // =====================================================
  // CLEANUP UTILITY - Remove all roles except SuperAdmin
  // =====================================================
  Future<void> cleanupAllRoles(String collegeId) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('colleges')
          .doc(collegeId)
          .collection('role_permissions')
          .get();
      WriteBatch batch = _firestore.batch();
      int deletedCount = 0;

      for (var doc in snapshot.docs) {
        if (doc.id != 'SuperAdmin') {
          batch.delete(doc.reference);
          deletedCount++;
        }
      }

      if (deletedCount > 0) {
        await batch.commit();
        print("✅ Cleaned up $deletedCount roles (kept SuperAdmin)");
      } else {
        print("✅ No roles to clean up");
      }
    } catch (e) {
      print("🚨 CLEANUP ERROR: $e");
      throw Exception('Failed to clean up roles: $e');
    }
  }

  // =====================================================
  // UTILITY METHODS
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

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
