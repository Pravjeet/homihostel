import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/fee.dart';

/// Mess-fee status records, at `colleges/{collegeId}/feeRecords/{period_uid}`.
///
/// The app records *status*, never money. There is no gateway and no
/// transaction id — someone in the office saw the payment arrive and ticked a
/// box, and this stores that fact plus when.
///
/// A row exists only for a student who has been marked paid. Absence is
/// unpaid. That means a new month costs zero writes, and "unpaid" can never be
/// stale because nothing was generated ahead of time.
class FeeService {
  FeeService._();
  static final FeeService instance = FeeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String collegeId) =>
      _db.collection('colleges').doc(collegeId).collection('feeRecords');

  // ------------------------------ reads ------------------------------

  /// Every paid record for one month.
  ///
  /// Not ordered in the query: an `orderBy` alongside the `where` would need a
  /// composite index, and the page joins these against the student list
  /// anyway, so their order here is irrelevant.
  Stream<List<FeeRecord>> watchPeriod(String collegeId, String period) =>
      _col(collegeId)
          .where('period', isEqualTo: period)
          .snapshots()
          .map(
            (s) => s.docs.map((d) => FeeRecord.fromMap(d.id, d.data())).toList(),
          );

  /// Every record from [fromPeriod] onwards, for the dashboard's trend and
  /// recent-payments list.
  ///
  /// A single-field range on `period` — no composite index needed, which is
  /// why the period is a sortable `YYYY-MM` string rather than a Timestamp.
  Stream<List<FeeRecord>> watchSince(String collegeId, String fromPeriod) =>
      _col(collegeId)
          .where('period', isGreaterThanOrEqualTo: fromPeriod)
          .snapshots()
          .map(
            (s) => s.docs.map((d) => FeeRecord.fromMap(d.id, d.data())).toList(),
          );

  /// One student's own history, newest month first.
  Stream<List<FeeRecord>> watchMine(String collegeId, String uid) =>
      _col(collegeId).where('studentUid', isEqualTo: uid).snapshots().map((s) {
        final list = s.docs
            .map((d) => FeeRecord.fromMap(d.id, d.data()))
            .toList();
        // Periods are `YYYY-MM`, so a plain string sort is chronological.
        list.sort((a, b) => b.period.compareTo(a.period));
        return list;
      });

  // ------------------------------ writes -----------------------------

  /// Records a student as paid for [period].
  ///
  /// The document id is derived from period + uid, so marking twice updates
  /// one row rather than creating a duplicate — which matters when two clerks
  /// work through the same list.
  Future<void> markPaid({
    required String collegeId,
    required AppUser student,
    required AppUser recordedBy,
    required String period,
    required num amount,
    DateTime? paidOn,
    String? method,
    String? note,
  }) {
    final id = feeDocId(period, student.uid);
    final record = FeeRecord(
      id: id,
      studentUid: student.uid,
      studentName: student.name,
      studentRegNo: student.enrollmentNo,
      hostelId: student.hostelId,
      hostelName: student.hostelName,
      roomNumber: student.roomNumber,
      trade: student.trade,
      batch: student.batch,
      sem: student.sem,
      period: period,
      amount: amount,
      paidOn: paidOn ?? DateTime.now(),
      method: (method == null || method.trim().isEmpty) ? null : method.trim(),
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      recordedByUid: recordedBy.uid,
      recordedByName: recordedBy.name,
    );

    return _col(collegeId).doc(id).set({
      ...record.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Undoes a payment record, returning the student to unpaid.
  ///
  /// Deleting rather than flipping a flag keeps one meaning for "no row", so
  /// the roster never has to ask whether a row means unpaid or un-marked.
  Future<void> markUnpaid({
    required String collegeId,
    required String period,
    required String studentUid,
  }) => _col(collegeId).doc(feeDocId(period, studentUid)).delete();

  /// Marks a whole list paid in one go, for a warden working down a hostel.
  ///
  /// Chunked at 400 because a Firestore batch caps at 500 operations.
  Future<int> markManyPaid({
    required String collegeId,
    required List<AppUser> students,
    required AppUser recordedBy,
    required String period,
    required num amount,
    DateTime? paidOn,
  }) async {
    if (students.isEmpty) return 0;
    final when = paidOn ?? DateTime.now();

    for (var i = 0; i < students.length; i += 400) {
      final end = (i + 400).clamp(0, students.length);
      final batch = _db.batch();
      for (final s in students.sublist(i, end)) {
        final id = feeDocId(period, s.uid);
        batch.set(_col(collegeId).doc(id), {
          ...FeeRecord(
            id: id,
            studentUid: s.uid,
            studentName: s.name,
            studentRegNo: s.enrollmentNo,
            hostelId: s.hostelId,
            hostelName: s.hostelName,
            roomNumber: s.roomNumber,
            trade: s.trade,
            batch: s.batch,
            sem: s.sem,
            period: period,
            amount: amount,
            paidOn: when,
            recordedByUid: recordedBy.uid,
            recordedByName: recordedBy.name,
          ).toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    return students.length;
  }

  /// Joins the student list against a month's records.
  ///
  /// Lives here rather than in the page so the "missing row means unpaid"
  /// rule has exactly one implementation.
  static List<FeeStanding> standingsFor({
    required List<AppUser> students,
    required List<FeeRecord> records,
  }) {
    final byUid = {for (final r in records) r.studentUid: r};
    return students
        .map(
          (s) => FeeStanding(
            studentUid: s.uid,
            studentName: s.name,
            studentRegNo: s.enrollmentNo,
            hostelName: s.hostelName,
            roomNumber: s.roomNumber,
            record: byUid[s.uid],
          ),
        )
        .toList();
  }
}
