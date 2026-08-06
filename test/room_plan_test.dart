import 'package:flutter_test/flutter_test.dart';

import 'package:hostel_app/models/hostel.dart';

/// [RoomPlan.build] is what turns the "add hostel" form into real room
/// documents, and the hostel editor's confirmation line (`rangeSummary`) has
/// to describe the exact same thing it will create — see
/// hostel_editor_dialog.dart. Both were rewritten to support multiple room
/// types sharing a building, which is exactly the kind of floor-numbering
/// arithmetic that goes quietly wrong under a fencepost error.
void main() {
  group('RoomBlock.floorCount', () {
    test('divides evenly when totalRooms is a multiple of roomsPerFloor', () {
      const block = RoomBlock(capacity: 2, totalRooms: 50, roomsPerFloor: 25);
      expect(block.floorCount, 2);
    });

    test('rounds up when the last floor is short', () {
      // 61 rooms at 25/floor: 25, 25, 11 — three floors, not two.
      const block = RoomBlock(capacity: 1, totalRooms: 61, roomsPerFloor: 25);
      expect(block.floorCount, 3);
    });

    test('is zero when roomsPerFloor is zero, not a division error', () {
      const block = RoomBlock(capacity: 2, totalRooms: 25, roomsPerFloor: 0);
      expect(block.floorCount, 0);
    });

    test('totalBeds is rooms times capacity', () {
      const block = RoomBlock(capacity: 3, totalRooms: 10, roomsPerFloor: 10);
      expect(block.totalBeds, 30);
    });
  });

  group('RoomPlan.build — single block', () {
    test('numbers rooms floor-prefixed starting at floor 1', () {
      const plan = RoomPlan(
        blocks: [RoomBlock(capacity: 2, totalRooms: 3, roomsPerFloor: 2)],
      );
      final rooms = plan.build();
      // Floor 1 gets 2 rooms (101, 102), floor 2 gets the remaining 1 (201).
      expect(
        rooms.map((r) => r.number).toList(),
        ['101', '102', '201'],
      );
      expect(rooms.every((r) => r.capacity == 2), isTrue);
    });

    test('every generated room carries the block\'s features', () {
      const plan = RoomPlan(
        blocks: [
          RoomBlock(
            capacity: 1,
            totalRooms: 2,
            roomsPerFloor: 2,
            features: ['Ceiling Fan'],
          ),
        ],
      );
      final rooms = plan.build();
      expect(rooms, everyElement(predicate<Room>((r) => r.features.contains('Ceiling Fan'))));
    });

    test('room id matches its number, so duplicates are structurally impossible', () {
      const plan = RoomPlan(
        blocks: [RoomBlock(capacity: 2, totalRooms: 4, roomsPerFloor: 2)],
      );
      for (final r in plan.build()) {
        expect(r.id, r.number);
      }
    });

    test('a block with zero rooms produces nothing', () {
      const plan = RoomPlan(
        blocks: [RoomBlock(capacity: 2, totalRooms: 0, roomsPerFloor: 25)],
      );
      expect(plan.build(), isEmpty);
    });
  });

  group('RoomPlan.build — multiple room types in one building', () {
    test('the second block starts on the floor after the first block ends', () {
      const plan = RoomPlan(
        blocks: [
          // 2 floors of 3-seaters (floors 1-2), then singles start at floor 3.
          RoomBlock(capacity: 3, totalRooms: 50, roomsPerFloor: 25),
          RoomBlock(capacity: 1, totalRooms: 10, roomsPerFloor: 25),
        ],
      );
      final rooms = plan.build();
      final threeSeaterFloors = rooms
          .where((r) => r.capacity == 3)
          .map((r) => r.floor)
          .toSet();
      final singleFloors =
          rooms.where((r) => r.capacity == 1).map((r) => r.floor).toSet();

      expect(threeSeaterFloors, {1, 2});
      expect(singleFloors, {3});
      // No floor is shared between two room types.
      expect(threeSeaterFloors.intersection(singleFloors), isEmpty);
    });

    test('plan.floors sums every block\'s floor count', () {
      const plan = RoomPlan(
        blocks: [
          RoomBlock(capacity: 3, totalRooms: 50, roomsPerFloor: 25), // 2
          RoomBlock(capacity: 1, totalRooms: 61, roomsPerFloor: 25), // 3
        ],
      );
      expect(plan.floors, 5);
    });

    test('plan.totalRooms and totalBeds sum across blocks', () {
      const plan = RoomPlan(
        blocks: [
          RoomBlock(capacity: 3, totalRooms: 50, roomsPerFloor: 25),
          RoomBlock(capacity: 1, totalRooms: 10, roomsPerFloor: 25),
        ],
      );
      expect(plan.totalRooms, 60);
      expect(plan.totalBeds, 50 * 3 + 10 * 1);
    });
  });

  group('RoomPlan.rangeSummary', () {
    test('describes an empty plan without crashing', () {
      expect(const RoomPlan().rangeSummary, '—');
    });

    test('names the seater type and floor range for each block', () {
      const plan = RoomPlan(
        blocks: [
          RoomBlock(capacity: 3, totalRooms: 50, roomsPerFloor: 25),
          RoomBlock(capacity: 1, totalRooms: 10, roomsPerFloor: 25),
        ],
      );
      final summary = plan.rangeSummary;
      expect(summary, contains('3 Seater'));
      expect(summary, contains('Single'));
    });

    test('a single-capacity block is labelled "Single", not "1 Seater"', () {
      const plan = RoomPlan(
        blocks: [RoomBlock(capacity: 1, totalRooms: 5, roomsPerFloor: 25)],
      );
      expect(plan.rangeSummary, contains('Single'));
      expect(plan.rangeSummary, isNot(contains('1 Seater')));
    });
  });
}
