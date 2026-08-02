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

/// The blueprint the "add hostel" form fills in. Kept as a plain value object
/// so the preview in the UI and the actual write use the exact same maths —
/// what you see in the preview is literally what gets created.
class RoomPlan {
  final int floors;
  final int roomsPerFloor;
  final int capacity;
  final List<String> features;

  /// Floor-prefixed numbering: floor 1 -> 101, 102...; floor 2 -> 201...
  /// Floors are numbered from 1 (ground floor is floor 1 here).
  const RoomPlan({
    required this.floors,
    required this.roomsPerFloor,
    required this.capacity,
    this.features = const [],
  });

  int get totalRooms => floors * roomsPerFloor;
  int get totalBeds => totalRooms * capacity;

  /// Generates every room this plan describes, in order.
  List<Room> build() {
    final rooms = <Room>[];
    for (var floor = 1; floor <= floors; floor++) {
      for (var i = 1; i <= roomsPerFloor; i++) {
        final number = '${floor * 100 + i}';
        rooms.add(
          Room(
            id: number,
            number: number,
            floor: floor,
            capacity: capacity,
            features: features,
          ),
        );
      }
    }
    return rooms;
  }

  /// Human summary for the confirmation line, e.g.
  /// "101–125, 201–225, 301–325".
  String get rangeSummary {
    if (floors <= 0 || roomsPerFloor <= 0) return '—';
    final parts = <String>[];
    for (var floor = 1; floor <= floors && floor <= 4; floor++) {
      final first = floor * 100 + 1;
      final last = floor * 100 + roomsPerFloor;
      parts.add('$first–$last');
    }
    if (floors > 4) parts.add('…');
    return parts.join(', ');
  }
}
