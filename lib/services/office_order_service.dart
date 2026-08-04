import 'dart:convert';
import 'dart:typed_data';

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

  /// Publishes an order as a photo, base64-encoded into the document itself
  /// — there's no Firebase Storage on the free plan. [imageBytes] should
  /// already be under the ~700 KB cap the publish form enforces; base64 adds
  /// ~33% on top of that, and a Firestore document tops out around 1 MB.
  Future<String> publish({
    required String collegeId,
    required AppUser author,
    required String orderNo,
    required String title,
    required Uint8List imageBytes,
    required String imageMimeType,
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
      imageBase64: base64Encode(imageBytes),
      imageMimeType: imageMimeType,
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
