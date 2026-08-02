import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/identity.dart';
import '../core/permissions.dart';
import '../models/app_role.dart';
import '../models/app_user.dart';

/// All authentication + provisioning logic. Widgets never touch
/// FirebaseAuth/Firestore directly.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  // ---------------------------------------------------------------------
  // Registration: creates the college workspace + its SuperAdmin.
  // ---------------------------------------------------------------------
  Future<void> registerCollege({
    required String institutionName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw AuthFailure('Account could not be created. Please try again.');
    }

    await user.updateDisplayName(adminName.trim());

    final slug = institutionName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final collegeId =
        '${slug.isEmpty ? 'college' : slug}-'
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    final batch = _db.batch();
    final collegeRef = _db.collection('colleges').doc(collegeId);

    batch.set(collegeRef, {
      'name': institutionName.trim(),
      'ownerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // The one system role. It implicitly holds every permission; we still
    // write them out so the Roles screen can display it honestly.
    batch.set(collegeRef.collection('roles').doc('super-admin'), {
      'name': 'Super Admin',
      'description': 'Full access to everything. Cannot be edited or deleted.',
      'permissions': Perm.all,
      'isSystem': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Starter roles so the admin isn't staring at an empty screen.
    kRoleTemplates.forEach((name, perms) {
      final id = name.toLowerCase().replaceAll(' ', '-');
      batch.set(collegeRef.collection('roles').doc(id), {
        'name': name,
        'description': 'Starter template — edit the permissions to taste.',
        'permissions': perms,
        'isSystem': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    batch.set(_db.collection('users').doc(user.uid), {
      'uid': user.uid,
      'name': adminName.trim(),
      'email': email.trim(),
      'collegeId': collegeId,
      'roleId': 'super-admin',
      'roleName': 'Super Admin',
      'isSuperAdmin': true,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ---------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------
  /// [identifier] may be a real email address or a registration number —
  /// see [Identity]. The number is mapped to a synthetic address before it
  /// reaches Firebase.
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: Identity.toAuthEmail(identifier),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Only meaningful for real addresses. A synthetic one has no inbox, so we
  /// refuse rather than silently pretending to send.
  Future<void> sendPasswordReset(String identifier) async {
    final email = Identity.toAuthEmail(identifier);
    if (Identity.isSynthetic(email)) {
      throw AuthFailure(
        'Accounts that sign in with a registration number have no email '
        'inbox, so a reset link can\'t be sent. Ask your hostel administrator '
        'to set a new password for you.',
      );
    }
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ---------------------------------------------------------------------
  // Session loading
  // ---------------------------------------------------------------------

  /// Live view of the signed-in user's profile document.
  Stream<AppUser?> watchProfile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromMap(d.id, d.data()!) : null);

  /// Live view of a role document, so a permission change applied by the
  /// admin reaches the affected user's sidebar without them re-logging in.
  Stream<AppRole?> watchRole(String collegeId, String roleId) => _db
      .collection('colleges')
      .doc(collegeId)
      .collection('roles')
      .doc(roleId)
      .snapshots()
      .map((d) => d.exists ? AppRole.fromMap(d.id, d.data()!) : null);

  Future<String> collegeName(String collegeId) async {
    final doc = await _db.collection('colleges').doc(collegeId).get();
    return doc.data()?['name'] as String? ?? 'Institution';
  }

  // ---------------------------------------------------------------------
  // Creating a sub-user without kicking the admin out of their own session.
  //
  // `createUserWithEmailAndPassword` signs the *new* user in on the default
  // FirebaseAuth instance — which would log the admin out. Spinning up a
  // secondary FirebaseApp gives us an isolated auth instance to do the
  // creation in, then we throw it away.
  //
  // NOTE: this is the right pragmatic call while you have no backend. The
  // production-grade answer is a Cloud Function using the Admin SDK; move to
  // that when you can, because it also lets you delete Auth accounts.
  // ---------------------------------------------------------------------
  /// Spins up an isolated FirebaseApp for provisioning accounts.
  ///
  /// Creating one of these is expensive — on web it bootstraps a whole JS SDK
  /// app. A bulk import should open **one** and pass it to every
  /// [createSubUser] call, then [closeProvisioningApp] at the end. Doing it
  /// per row is what made a 30-row import take minutes.
  Future<FirebaseApp> openProvisioningApp() => Firebase.initializeApp(
    name: 'user-provisioning-${DateTime.now().microsecondsSinceEpoch}',
    options: Firebase.app().options,
  );

  Future<void> closeProvisioningApp(FirebaseApp app) async {
    try {
      await FirebaseAuth.instanceFor(app: app).signOut();
    } catch (_) {
      // Nothing signed in; nothing to do.
    }
    await app.delete();
  }

  Future<AppUser> createSubUser({
    required String name,
    required String email,
    required String password,
    required String collegeId,
    required String roleId,
    required String roleName,
    String? phone,
    String? gender,
    String? enrollmentNo,

    /// Extra profile fields written in the *same* document write, so a bulk
    /// import doesn't need a second round trip per student.
    Map<String, dynamic>? extra,

    /// Reuse an app from [openProvisioningApp]. When supplied it is NOT
    /// deleted here — the caller owns its lifetime.
    FirebaseApp? app,
  }) async {
    final owned = app == null;
    FirebaseApp? temp = app;
    try {
      temp ??= await openProvisioningApp();
      final cred = await FirebaseAuth.instanceFor(app: temp)
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      final uid = cred.user!.uid;
      await cred.user!.updateDisplayName(name.trim());

      final profile = AppUser(
        uid: uid,
        name: name.trim(),
        email: email.trim(),
        collegeId: collegeId,
        roleId: roleId,
        roleName: roleName,
        phone: phone,
        gender: gender,
        enrollmentNo: enrollmentNo,
      );

      await _db.collection('users').doc(uid).set({
        ...profile.toMap(),
        ...?extra,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseAuth.instanceFor(app: temp).signOut();
      return profile;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_friendly(e));
    } finally {
      // Only tear down an app we created ourselves.
      if (owned) await temp?.delete();
    }
  }

  /// Maps Firebase's error codes to something a human can act on.
  static String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address doesn\'t look valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  static String describeError(Object e) {
    if (e is FirebaseAuthException) return _friendly(e);
    if (e is AuthFailure) return e.message;
    if (e is FirebaseException) {
      return e.code == 'permission-denied'
          ? 'You don\'t have permission to do that.'
          : (e.message ?? 'Database error.');
    }
    return 'Something went wrong. Please try again.';
  }
}

class AuthFailure implements Exception {
  final String message;
  AuthFailure(this.message);
  @override
  String toString() => message;
}
