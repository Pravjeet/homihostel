import 'package:cloud_firestore/cloud_firestore.dart';

/// Who a hostel accommodates. Stored as the enum `name` string.
enum HostelGender { boys, girls, coed }

extension HostelGenderX on HostelGender {
  String get label => switch (this) {
    HostelGender.boys => 'Boys',
    HostelGender.girls => 'Girls',
    HostelGender.coed => 'Co-ed',
  };

  static HostelGender parse(String? v) => HostelGender.values.firstWhere(
    (e) => e.name == v,
    orElse: () => HostelGender.coed,
  );
}

/// Operational state of a single room.
enum RoomStatus { active, maintenance, reserved }

extension RoomStatusX on RoomStatus {
  String get label => switch (this) {
    RoomStatus.active => 'Active',
    RoomStatus.maintenance => 'Maintenance',
    RoomStatus.reserved => 'Reserved',
  };

  static RoomStatus parse(String? v) => RoomStatus.values.firstWhere(
    (e) => e.name == v,
    orElse: () => RoomStatus.active,
  );
}

/// Things provided at the *building* level.
const List<String> kHostelAmenities = [
  'WiFi',
  'Mess',
  'Common Room',
  'Laundry',
  'Gym',
  'Reading Room',
  'Water Cooler / RO',
  'Power Backup',
  'CCTV',
  'Security Guard',
  'Parking',
  'Medical Room',
  'Indoor Games',
  'Lift',
];

/// Things provided at the *room* level. These vary room to room, which is why
/// they're separate from the hostel list — an AC room and a non-AC room can
/// sit on the same floor.
const List<String> kRoomFeatures = [
  'AC',
  'Attached Bathroom',
  'Balcony',
  'Study Table',
  'Almirah / Wardrobe',
  'Ceiling Fan',
  'Geyser',
];

// =====================================================================
// Hostel
// =====================================================================

class Hostel {
  final String id;
  final String name;

  /// Short label used in room codes and tight UI, e.g. "A".
  final String code;

  final HostelGender gender;
  final int floors;
  final List<String> amenities;
  final String? wardenUid;
  final String? wardenName;
  final String? address;

  /// Denormalised counters, kept in step by [HostelService] whenever rooms
  /// are added or removed. Storing them avoids reading every room document
  /// just to render the hostel list.
  final int roomCount;
  final int bedCount;
  final int occupiedBeds;

  final DateTime? createdAt;

  const Hostel({
    required this.id,
    required this.name,
    required this.code,
    this.gender = HostelGender.coed,
    this.floors = 1,
    this.amenities = const [],
    this.wardenUid,
    this.wardenName,
    this.address,
    this.roomCount = 0,
    this.bedCount = 0,
    this.occupiedBeds = 0,
    this.createdAt,
  });

  factory Hostel.fromMap(String id, Map<String, dynamic> m) => Hostel(
    id: id,
    name: m['name'] as String? ?? 'Unnamed hostel',
    code: m['code'] as String? ?? '',
    gender: HostelGenderX.parse(m['gender'] as String?),
    floors: (m['floors'] as num?)?.toInt() ?? 1,
    amenities: ((m['amenities'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    wardenUid: m['wardenUid'] as String?,
    wardenName: m['wardenName'] as String?,
    address: m['address'] as String?,
    roomCount: (m['roomCount'] as num?)?.toInt() ?? 0,
    bedCount: (m['bedCount'] as num?)?.toInt() ?? 0,
    occupiedBeds: (m['occupiedBeds'] as num?)?.toInt() ?? 0,
    createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'code': code,
    'gender': gender.name,
    'floors': floors,
    'amenities': amenities,
    'wardenUid': wardenUid,
    'wardenName': wardenName,
    'address': address,
    'roomCount': roomCount,
    'bedCount': bedCount,
    'occupiedBeds': occupiedBeds,
  };

  int get freeBeds => (bedCount - occupiedBeds).clamp(0, bedCount);

  /// 0.0 – 1.0. Guarded against divide-by-zero on a hostel with no rooms.
  double get occupancy => bedCount == 0 ? 0 : occupiedBeds / bedCount;

  Hostel copyWith({
    String? name,
    String? code,
    HostelGender? gender,
    int? floors,
    List<String>? amenities,
    String? wardenUid,
    String? wardenName,
    String? address,
  }) => Hostel(
    id: id,
    name: name ?? this.name,
    code: code ?? this.code,
    gender: gender ?? this.gender,
    floors: floors ?? this.floors,
    amenities: amenities ?? this.amenities,
    wardenUid: wardenUid ?? this.wardenUid,
    wardenName: wardenName ?? this.wardenName,
    address: address ?? this.address,
    roomCount: roomCount,
    bedCount: bedCount,
    occupiedBeds: occupiedBeds,
    createdAt: createdAt,
  );
}

// =====================================================================
// Room
// =====================================================================

class Room {
  /// Document id — the room number itself ("101"), which makes duplicates
  /// impossible within a hostel and keeps paths readable.
  final String id;

  final String number;
  final int floor;
  final int capacity;
  final List<String> features;
  final RoomStatus status;

  /// UIDs of students currently allotted. The allotment module will own
  /// writes to this; for now it lets us show real occupancy.
  final List<String> occupantUids;

  final num? rentPerBed;
  final String? note;

  const Room({
    required this.id,
    required this.number,
    required this.floor,
    required this.capacity,
    this.features = const [],
    this.status = RoomStatus.active,
    this.occupantUids = const [],
    this.rentPerBed,
    this.note,
  });

  factory Room.fromMap(String id, Map<String, dynamic> m) => Room(
    id: id,
    number: m['number'] as String? ?? id,
    floor: (m['floor'] as num?)?.toInt() ?? 0,
    capacity: (m['capacity'] as num?)?.toInt() ?? 1,
    features: ((m['features'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    status: RoomStatusX.parse(m['status'] as String?),
    occupantUids: ((m['occupantUids'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    rentPerBed: m['rentPerBed'] as num?,
    note: m['note'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'number': number,
    'floor': floor,
    'capacity': capacity,
    'features': features,
    'status': status.name,
    'occupantUids': occupantUids,
    'rentPerBed': rentPerBed,
    'note': note,
  };

  int get occupied => occupantUids.length;
  int get free => (capacity - occupied).clamp(0, capacity);
  bool get isFull => free == 0;
  bool get isAvailable => status == RoomStatus.active && !isFull;

  /// "2 Seater" / "Single" — matches the phrasing in the student mockup.
  String get capacityLabel =>
      capacity == 1 ? 'Single' : '$capacity Seater';

  Room copyWith({
    int? capacity,
    List<String>? features,
    RoomStatus? status,
    List<String>? occupantUids,
    num? rentPerBed,
    String? note,
  }) => Room(
    id: id,
    number: number,
    floor: floor,
    capacity: capacity ?? this.capacity,
    features: features ?? this.features,
    status: status ?? this.status,
    occupantUids: occupantUids ?? this.occupantUids,
    rentPerBed: rentPerBed ?? this.rentPerBed,
    note: note ?? this.note,
  );
}

// =====================================================================
// Room generation
// =====================================================================

/// One uniform slab of rooms: some number of rooms, of one capacity, on a
/// span of floors. A real building is described as a *list* of these — a
/// girls' hostel with 60 three-seater rooms and 61 singles in the same block
/// is two [RoomBlock]s, and a building where every floor is laid out
/// differently is one block per floor. The common case (identical floors)
/// is still just one block, so the simple hostel isn't punished for the
/// flexibility.
class RoomBlock {
  final int fromFloor;
  final int toFloor;
  final int roomsPerFloor;
  final int capacity;
  final List<String> features;

  const RoomBlock({
    required this.fromFloor,
    required this.toFloor,
    required this.roomsPerFloor,
    required this.capacity,
    this.features = const [],
  });

  int get floorCount => (toFloor - fromFloor + 1).clamp(0, 1 << 20);
  int get totalRooms => floorCount * roomsPerFloor;
  int get totalBeds => totalRooms * capacity;

  RoomBlock copyWith({
    int? fromFloor,
    int? toFloor,
    int? roomsPerFloor,
    int? capacity,
    List<String>? features,
  }) => RoomBlock(
    fromFloor: fromFloor ?? this.fromFloor,
    toFloor: toFloor ?? this.toFloor,
    roomsPerFloor: roomsPerFloor ?? this.roomsPerFloor,
    capacity: capacity ?? this.capacity,
    features: features ?? this.features,
  );
}

/// The blueprint the "add hostel" form fills in. Kept as a plain value object
/// so the preview in the UI and the actual write use the exact same maths —
/// what you see in the preview is literally what gets created.
class RoomPlan {
  final List<RoomBlock> blocks;

  const RoomPlan({this.blocks = const []});

  int get floors => blocks.isEmpty
      ? 0
      : blocks.map((b) => b.toFloor).reduce((a, b) => a > b ? a : b);

  int get totalRooms => blocks.fold(0, (acc, b) => acc + b.totalRooms);
  int get totalBeds => blocks.fold(0, (acc, b) => acc + b.totalBeds);

  /// Generates every room every block describes, in order.
  ///
  /// Floor-prefixed numbering: floor 1 -> 101, 102...; floor 2 -> 201... A
  /// running counter is kept *per floor* rather than per block, so a second
  /// block that lands on a floor an earlier block already touched (the mixed
  /// 3-seater/single case) continues the numbering instead of colliding with
  /// it.
  List<Room> build() {
    final nextOnFloor = <int, int>{};
    final rooms = <Room>[];
    for (final block in blocks) {
      for (var floor = block.fromFloor; floor <= block.toFloor; floor++) {
        var i = nextOnFloor[floor] ?? 0;
        for (var k = 0; k < block.roomsPerFloor; k++) {
          i++;
          final number = '${floor * 100 + i}';
          rooms.add(
            Room(
              id: number,
              number: number,
              floor: floor,
              capacity: block.capacity,
              features: block.features,
            ),
          );
        }
        nextOnFloor[floor] = i;
      }
    }
    return rooms;
  }

  /// Human summary for the confirmation line, e.g.
  /// "101–130 (3 Seater), 131–145 (Single), 201–230 (3 Seater)".
  String get rangeSummary {
    final nextOnFloor = <int, int>{};
    final parts = <String>[];
    var truncated = false;
    for (final block in blocks) {
      if (block.roomsPerFloor <= 0 || block.floorCount <= 0) continue;
      for (var floor = block.fromFloor; floor <= block.toFloor; floor++) {
        final start = (nextOnFloor[floor] ?? 0) + 1;
        final end = start + block.roomsPerFloor - 1;
        nextOnFloor[floor] = end;
        if (parts.length >= 6) {
          truncated = true;
          continue;
        }
        final label = block.capacity == 1 ? 'Single' : '${block.capacity} Seater';
        parts.add('${floor * 100 + start}–${floor * 100 + end} ($label)');
      }
    }
    if (parts.isEmpty) return '—';
    return truncated ? '${parts.join(', ')}, …' : parts.join(', ');
  }
}
