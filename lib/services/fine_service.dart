import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/fine.dart';
import '../models/office_order.dart';
import 'audit_service.dart';

/// Fines live under their college:
///   colleges/{collegeId}/fines/{fineId}
///
/// A flat collection rather than a subcollection per student, because the
/// dashboard's whole job is aggregating across everyone — one query beats a
/// collection-group scan. Two read paths, same as [RequestService]: a student
/// may only ever query their own, and the Firestore rules enforce that the
/// where-clause is present.
class FineService {
  FineService._();
  static final FineService instance = FineService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('fines');

  CollectionReference<Map<String, dynamic>> _ordersCol(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('officeOrders');

  // ------------------------------ reads ------------------------------

  /// Everything, newest first — for staff holding fines.viewAll.
  Stream<List<Fine>> watchAll(String collegeId) => _col(collegeId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Fine.fromMap(d.id, d.data())).toList());

  /// One student's own fines. Not ordered in the query — an `orderBy` next to
  /// the `where` would need a composite index, and sorting a handful of
  /// documents client-side is free.
  Stream<List<Fine>> watchMine(String collegeId, String uid) =>
      _col(collegeId).where('studentUid', isEqualTo: uid).snapshots().map((s) {
        final list = s.docs
            .map((d) => Fine.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) {
          final at = a.createdAt, bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        return list;
      });

  // ------------------------------ writes -----------------------------

  /// Imposes a fine and publishes its office order together, in one batch.
  ///
  /// The two documents are created with pre-generated ids so each can carry
  /// the other's: `fine.officeOrderId` and `order.fineId`. Every fine raised
  /// this way has a real order behind it — there is no path to impose a fine
  /// without one, because in this college a fine only exists because an order
  /// was issued for it.
  Future<({String fineId, String orderId})> imposeWithOfficeOrder({
    required String collegeId,
    required AppUser student,
    required AppUser imposedBy,
    required num amount,
    required String category,
    String reason = '',
    required String orderNo,
    required String orderTitle,
    required Uint8List orderImageBytes,
    required String orderImageMimeType,
    String? orderDescription,
    DateTime? orderDate,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('A fine must be for more than zero.');
    }

    final fineRef = _col(collegeId).doc();
    final orderRef = _ordersCol(collegeId).doc();

    final fine = Fine(
      id: fineRef.id,
      studentUid: student.uid,
      studentName: student.name,
      studentRegNo: student.enrollmentNo,
      hostelId: student.hostelId,
      hostelName: student.hostelName,
      roomNumber: student.roomNumber,
      trade: student.trade,
      batch: student.batch,
      sem: student.sem,
      // Fall back to parsing the address, so a student whose `state` field was
      // never filled in still lands on the right bar instead of "Not set".
      state: student.state ?? stateFromAddress(student.address),
      amount: amount,
      category: category,
      reason: reason.trim(),
      officeOrderId: orderRef.id,
      officeOrderNo: orderNo.trim(),
      imposedByUid: imposedBy.uid,
      imposedByName: imposedBy.name,
    );

    final order = OfficeOrder(
      id: orderRef.id,
      orderNo: orderNo.trim(),
      title: orderTitle.trim(),
      description: (orderDescription == null || orderDescription.trim().isEmpty)
          ? null
          : orderDescription.trim(),
      orderDate: orderDate,
      imageBase64: base64Encode(orderImageBytes),
      imageMimeType: orderImageMimeType,
      postedByUid: imposedBy.uid,
      postedByName: imposedBy.name,
      studentUid: student.uid,
      studentName: student.name,
      studentRegNo: student.enrollmentNo,
      fineId: fineRef.id,
      fineAmount: amount,
      fineCategory: category,
    );

    final batch = _db.batch();
    batch.set(fineRef, {...fine.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    batch.set(orderRef, {...order.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    await batch.commit();

    // No `before` — the fine did not exist, so undo deletes it.
    await AuditService.instance.record(
      collegeId: collegeId,
      actor: imposedBy,
      action: 'fine.impose',
      summary: 'Fined ${student.name} ₹$amount for $category '
          '(order $orderNo)',
      targetLabel: student.name,
      path: 'colleges/$collegeId/fines/${fineRef.id}',
      reversible: true,
    );

    return (fineId: fineRef.id, orderId: orderRef.id);
  }

  /// Marks a fine paid or waived, recording who decided.
  Future<void> setStatus({
    required String collegeId,
    required Fine fine,
    required FineStatus status,
    required AppUser handler,
  }) async {
    if (status == FineStatus.pending) {
      throw ArgumentError('Cannot move a fine back to unpaid.');
    }

    final ref = _col(collegeId).doc(fine.id);
    final before = (await ref.get()).data();

    await ref.update({
      'status': status.name,
      'resolvedByUid': handler.uid,
      'resolvedByName': handler.name,
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    await AuditService.instance.record(
      collegeId: collegeId,
      actor: handler,
      action: 'fine.${status.name}',
      summary: 'Marked ${fine.studentName}\'s ₹${fine.amount} fine '
          '${status.label.toLowerCase()}',
      targetLabel: fine.studentName,
      path: 'colleges/$collegeId/fines/${fine.id}',
      before: before,
      reversible: before != null,
    );
  }

  /// Removes a fine raised in error. Only while it's still unpaid — once money
  /// has changed hands the record stays.
  Future<void> remove({
    required String collegeId,
    required Fine fine,
    AppUser? actor,
  }) async {
    if (!fine.status.isOutstanding) {
      throw StateError(
        'This fine has already been settled and can no longer be removed.',
      );
    }

    final ref = _col(collegeId).doc(fine.id);
    final before = (await ref.get()).data();
    await ref.delete();

    if (actor != null) {
      await AuditService.instance.record(
        collegeId: collegeId,
        actor: actor,
        action: 'fine.delete',
        summary: 'Removed ${fine.studentName}\'s ₹${fine.amount} fine',
        targetLabel: fine.studentName,
        path: 'colleges/$collegeId/fines/${fine.id}',
        before: before,
        reversible: before != null,
      );
    }
  }

  /// Deletes every fine belonging to one student.
  ///
  /// Called when the student's own account is deleted — a fine pointing at a
  /// uid that no longer exists is an orphaned record nobody can act on, not a
  /// preserved one. Unlike [remove] this does NOT spare settled fines, same
  /// reasoning as [deleteAll]: the person the money was owed by is gone, so
  /// there is nothing left to collect against.
  Future<int> deleteForStudent(String collegeId, String uid) async {
    final snap =
        await _col(collegeId).where('studentUid', isEqualTo: uid).get();
    if (snap.docs.isEmpty) return 0;

    for (var i = 0; i < snap.docs.length; i += 400) {
      final end = (i + 400).clamp(0, snap.docs.length);
      final batch = _db.batch();
      for (final d in snap.docs.sublist(i, end)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    return snap.docs.length;
  }

  /// Deletes every fine in the college. For clearing test data.
  ///
  /// Unlike [remove] this does NOT spare settled fines — the point is a clean
  /// slate, and a reset that left the paid ones behind would be a confusing
  /// half-measure. Guarded in the UI by a typed confirmation, and by
  /// `fines.manage` in the rules.
  ///
  /// Chunked because a Firestore batch caps at 500 operations.
  Future<int> deleteAll(String collegeId) async {
    final snap = await _col(collegeId).get();
    if (snap.docs.isEmpty) return 0;

    for (var i = 0; i < snap.docs.length; i += 400) {
      final end = (i + 400).clamp(0, snap.docs.length);
      final batch = _db.batch();
      for (final d in snap.docs.sublist(i, end)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    return snap.docs.length;
  }
}
