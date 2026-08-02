import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/hostel_request.dart';

/// Requests live under their college:
///   colleges/{collegeId}/requests/{requestId}
///
/// Two read paths on purpose. A student may only ever query their own
/// (`watchMine`), and the Firestore rules enforce that the where-clause is
/// present — so dropping it client-side gets a permission error rather than
/// everyone's private complaints.
class RequestService {
  RequestService._();
  static final RequestService instance = RequestService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('requests');

  // ------------------------------ reads ------------------------------

  /// Everything, newest first — for staff holding requests.viewAll.
  Stream<List<HostelRequest>> watchAll(String collegeId) => _col(collegeId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => HostelRequest.fromMap(d.id, d.data()))
            .toList(),
      );

  /// One person's own requests.
  ///
  /// Deliberately not ordered in the query: adding `orderBy` alongside the
  /// `where` needs a composite index, and sorting 20 documents client-side is
  /// free. Fewer things to configure in the console.
  Stream<List<HostelRequest>> watchMine(String collegeId, String uid) =>
      _col(collegeId).where('raisedByUid', isEqualTo: uid).snapshots().map((s) {
        final list = s.docs
            .map((d) => HostelRequest.fromMap(d.id, d.data()))
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

  /// Raises a request. The author's name, registration number and room are
  /// copied onto the document so the staff queue can render a row without
  /// reading the user document for every entry.
  Future<String> raise({
    required String collegeId,
    required AppUser author,
    required RequestType type,
    required String subject,
    String details = '',
    DateTime? fromDate,
    DateTime? toDate,
    String? destination,
    String? category,
  }) async {
    final ref = _col(collegeId).doc();
    final request = HostelRequest(
      id: ref.id,
      type: type,
      status: RequestStatus.pending,
      raisedByUid: author.uid,
      raisedByName: author.name,
      raisedByRegNo: author.enrollmentNo,
      hostelName: author.hostelName,
      roomNumber: author.roomNumber,
      subject: subject.trim(),
      details: details.trim(),
      fromDate: fromDate,
      toDate: toDate,
      destination: destination?.trim(),
      category: category,
    );

    await ref.set({
      ...request.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Moves a request to a new status and records who did it.
  ///
  /// The allowed targets come from [RequestTypeX.nextStates], so a complaint
  /// can never be "approved" and leave can never be "resolved".
  Future<void> setStatus({
    required String collegeId,
    required HostelRequest request,
    required RequestStatus status,
    required AppUser handler,
    String? note,
  }) async {
    if (status == RequestStatus.pending) {
      throw ArgumentError('Cannot move a request back to pending.');
    }
    await _col(collegeId).doc(request.id).update({
      'status': status.name,
      'handledByUid': handler.uid,
      'handledByName': handler.name,
      'decisionNote': (note == null || note.trim().isEmpty)
          ? null
          : note.trim(),
      'handledAt': FieldValue.serverTimestamp(),
    });
  }

  /// A student withdrawing their own request. Only allowed while nobody has
  /// acted on it — once handled, it's part of the record.
  Future<void> withdraw({
    required String collegeId,
    required HostelRequest request,
  }) async {
    if (request.status != RequestStatus.pending) {
      throw StateError(
        'This request has already been handled and can no longer be '
        'withdrawn.',
      );
    }
    await _col(collegeId).doc(request.id).delete();
  }
}
