import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_app/models/app_user.dart';
import 'package:hostel_app/models/hostel.dart';

/// Membership vs. bed occupancy.
///
/// The distinction exists because a CSV import can put a whole intake into a
/// hostel with no rooms assigned — `occupiedBeds` stays zero while hundreds of
/// students are genuinely in the building. Getting this wrong under-reports a
/// hostel to empty, so it is worth pinning down.
void main() {
  AppUser student(
    String uid, {
    String? hostelId,
    String? roomId,
    bool isActive = true,
  }) => AppUser(
    uid: uid,
    name: uid,
    email: '$uid@x.test',
    collegeId: 'c1',
    roleId: 'r1',
    roleName: 'Student',
    isActive: isActive,
    hostelId: hostelId,
    roomId: roomId,
    roomNumber: roomId == null ? null : '101',
  );

  group('HostelHeadcount.byHostel', () {
    test('counts a hostel-only assignment, which has no bed at all', () {
      final heads = HostelHeadcount.byHostel([
        student('a', hostelId: 'h1'),
        student('b', hostelId: 'h1'),
        student('c', hostelId: 'h1'),
      ]);

      expect(heads['h1']!.total, 3);
      expect(heads['h1']!.withBed, 0);
      expect(heads['h1']!.awaitingRoom, 3);
    });

    test('separates those who hold a room from those who do not', () {
      final heads = HostelHeadcount.byHostel([
        student('a', hostelId: 'h1', roomId: 'r1'),
        student('b', hostelId: 'h1', roomId: 'r1'),
        student('c', hostelId: 'h1'),
      ]);

      expect(heads['h1']!.total, 3);
      expect(heads['h1']!.withBed, 2);
      expect(heads['h1']!.awaitingRoom, 1);
    });

    test('keeps hostels apart', () {
      final heads = HostelHeadcount.byHostel([
        student('a', hostelId: 'h1'),
        student('b', hostelId: 'h2', roomId: 'r9'),
        student('c', hostelId: 'h2'),
      ]);

      expect(heads['h1']!.total, 1);
      expect(heads['h2']!.total, 2);
      expect(heads['h2']!.withBed, 1);
    });

    test('ignores students with no hostel', () {
      final heads = HostelHeadcount.byHostel([
        student('a'),
        student('b', hostelId: ''),
        student('c', hostelId: 'h1'),
      ]);

      expect(heads.keys, ['h1']);
      expect(heads['h1']!.total, 1);
    });

    test('excludes deactivated accounts', () {
      // They cannot be allotted, so counting them would show a hostel as
      // fuller than it can actually be filled.
      final heads = HostelHeadcount.byHostel([
        student('a', hostelId: 'h1'),
        student('b', hostelId: 'h1', isActive: false),
        student('c', hostelId: 'h1', roomId: 'r1', isActive: false),
      ]);

      expect(heads['h1']!.total, 1);
      expect(heads['h1']!.withBed, 0);
    });

    test('a hostel with nobody in it is absent, not zero', () {
      final heads = HostelHeadcount.byHostel([student('a', hostelId: 'h1')]);

      expect(heads['h2'], isNull);
      // Callers substitute an empty count, which reads as zeros.
      expect(const HostelHeadcount().total, 0);
      expect(const HostelHeadcount().awaitingRoom, 0);
    });

    test('an empty roster yields no entries', () {
      expect(HostelHeadcount.byHostel(const []), isEmpty);
    });

    test('awaitingRoom never goes negative', () {
      // withBed cannot exceed total in practice, but the getter is used in UI
      // arithmetic and a negative badge would be nonsense.
      const odd = HostelHeadcount(total: 2, withBed: 5);
      expect(odd.awaitingRoom, 0);
    });

    test('a room without a hostel is not counted as membership', () {
      // isAllotted requires both, so a half-written user cannot inflate the
      // bed figure.
      final heads = HostelHeadcount.byHostel([student('a', roomId: 'r1')]);
      expect(heads, isEmpty);
    });

    test('scales over a full intake', () {
      final roster = [
        for (var i = 0; i < 400; i++)
          student('s$i', hostelId: 'h1', roomId: i < 60 ? 'r$i' : null),
      ];

      final heads = HostelHeadcount.byHostel(roster);
      expect(heads['h1']!.total, 400);
      expect(heads['h1']!.withBed, 60);
      expect(heads['h1']!.awaitingRoom, 340);
    });
  });
}
