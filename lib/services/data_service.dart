import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';
import 'allotment_service.dart';

/// Firestore reads/writes for roles and users.
class DataService {
  DataService._();
  static final DataService instance = DataService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _roles(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('roles');

  // ------------------------------- Roles -------------------------------

  Stream<List<AppRole>> watchRoles(String collegeId) =>
      _roles(collegeId).orderBy('name').snapshots().map(
        (s) => s.docs.map((d) => AppRole.fromMap(d.id, d.data())).toList(),
      );

  Future<void> createRole({
    required String collegeId,
    required String name,
    required String description,
    required Set<String> permissions,
  }) async {
    final id = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    if (id.isEmpty) throw Exception('Role name is required.');

    final ref = _roles(collegeId).doc(id);
    if ((await ref.get()).exists) {
      throw Exception('A role named "$name" already exists.');
    }
    await ref.set({
      'name': name.trim(),
      'description': description.trim(),
      'permissions': permissions.toList(),
      'isSystem': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateRole(String collegeId, AppRole role) async {
    if (role.isSystem) throw Exception('The Super Admin role cannot be edited.');
    await _roles(collegeId).doc(role.id).update({
      ...role.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a role and un-assigns everyone who held it, in one batch so you
  /// can never end up with users pointing at a role that no longer exists.
  Future<void> deleteRole(String collegeId, AppRole role) async {
    if (role.isSystem) {
      throw Exception('The Super Admin role cannot be deleted.');
    }
    final holders = await _db
        .collection('users')
        .where('collegeId', isEqualTo: collegeId)
        .where('roleId', isEqualTo: role.id)
        .get();

    final batch = _db.batch();
    for (final d in holders.docs) {
      batch.update(d.reference, {'roleId': null, 'roleName': null});
    }
    batch.delete(_roles(collegeId).doc(role.id));
    await batch.commit();
  }

  // ------------------------------- Users -------------------------------

  Stream<List<AppUser>> watchUsers(String collegeId) => _db
      .collection('users')
      .where('collegeId', isEqualTo: collegeId)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      );

  Future<void> updateUser(String uid, Map<String, dynamic> changes) => _db
      .collection('users')
      .doc(uid)
      .update({...changes, 'updatedAt': FieldValue.serverTimestamp()});

  /// One-shot lookup by email within a college. Used by the CSV importer to
  /// find an account it just created, since account creation happens on a
  /// throwaway Firebase instance and doesn't hand back a profile document.
  Future<AppUser?> findByEmail(String collegeId, String email) async {
    final snap = await _db
        .collection('users')
        .where('collegeId', isEqualTo: collegeId)
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AppUser.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  Future<void> setUserRole(String uid, AppRole? role) => updateUser(uid, {
    'roleId': role?.id,
    'roleName': role?.name,
  });

  Future<void> setUserActive(String uid, bool active) =>
      updateUser(uid, {'isActive': active});

  /// Removes the profile document. The Firebase Auth account survives — only
  /// the Admin SDK (a Cloud Function) can delete that. Deactivating is
  /// therefore the safer default, and what the UI offers first.
  Future<void> deleteUserProfile(String uid) =>
      _db.collection('users').doc(uid).delete();

  /// Bulk-removes profiles, freeing any rooms they held first.
  ///
  /// Vacating before deleting is not optional: dropping the user document
  /// while their uid is still in a room's `occupantUids` leaves the room
  /// showing a resident who no longer exists and the hostel's `occupiedBeds`
  /// permanently overcounted. That drift is invisible until someone wonders
  /// why a half-empty block reports itself full.
  ///
  /// Deliberately sequential and best-effort: one student whose room was
  /// deleted out from under them must not abort the other twenty-nine.
  ///
  /// As with [deleteUserProfile], the Firebase Auth accounts survive. See
  /// `tools/delete-students.js` for a wipe that removes those too.
  Future<BulkDeleteOutcome> deleteUserProfiles({
    required String collegeId,
    required List<AppUser> users,
    void Function(int done, int total)? onProgress,
  }) async {
    final failures = <String>[];
    var deleted = 0;
    var vacated = 0;
    var done = 0;

    for (final user in users) {
      if (user.isSuperAdmin) {
        failures.add('${user.name}: Super Admin accounts are never deleted');
        done++;
        onProgress?.call(done, users.length);
        continue;
      }

      if (user.isAllotted) {
        try {
          await AllotmentService.instance.vacate(
            collegeId: collegeId,
            student: user,
          );
          vacated++;
        } catch (e) {
          // Recorded, not fatal — better a stale room than a stranded profile.
          failures.add(
            '${user.name}: room not freed '
            '(${e is AllotmentFailure ? e.message : e})',
          );
        }
      }

      try {
        await deleteUserProfile(user.uid);
        deleted++;
      } catch (e) {
        failures.add('${user.name}: ${e is FirebaseException ? e.code : e}');
      }

      done++;
      onProgress?.call(done, users.length);
    }

    return BulkDeleteOutcome(
      deleted: deleted,
      vacated: vacated,
      failures: failures,
    );
  }
}

class BulkDeleteOutcome {
  final int deleted;
  final int vacated;
  final List<String> failures;
  const BulkDeleteOutcome({
    required this.deleted,
    required this.vacated,
    required this.failures,
  });
}
