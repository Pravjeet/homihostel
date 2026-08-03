import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/office_order.dart';

/// Office orders live under their college:
///   colleges/{collegeId}/officeOrders/{orderId}
///
/// Read by anyone with `officeOrders.view`, published by anyone with
/// `officeOrders.manage`. There is no update path — an order printed wrong is
/// deleted and re-published, same as notices, because an "edited" office order
/// is not a thing that exists on paper.
class OfficeOrderService {
  OfficeOrderService._();
  static final OfficeOrderService instance = OfficeOrderService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('officeOrders');

  // ------------------------------ reads ------------------------------

  /// Ordered by the date printed on the order, newest first — not by upload
  /// time, since a backlog of old orders is usually entered all at once.
  Stream<List<OfficeOrder>> watchAll(String collegeId) => _col(collegeId)
      .orderBy('orderDate', descending: true)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => OfficeOrder.fromMap(d.id, d.data())).toList(),
      );

  // ------------------------------ writes -----------------------------

  Future<String> publish({
    required String collegeId,
    required AppUser author,
    required String orderNo,
    required String title,
    required String pdfUrl,
    String? description,
    DateTime? orderDate,
  }) async {
    final ref = _col(collegeId).doc();
    final order = OfficeOrder(
      id: ref.id,
      orderNo: orderNo.trim(),
      title: title.trim(),
      description: (description == null || description.trim().isEmpty)
          ? null
          : description.trim(),
      orderDate: orderDate,
      pdfUrl: pdfUrl.trim(),
      postedByUid: author.uid,
      postedByName: author.name,
    );

    await ref.set({
      ...order.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> delete({
    required String collegeId,
    required String orderId,
  }) => _col(collegeId).doc(orderId).delete();
}
