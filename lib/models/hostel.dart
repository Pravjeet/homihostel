import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

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

/// All the rooms of one seater type — "60 rooms, 3 Seater". A real building
/// is described as a *list* of these, one per room type: a girls' hostel
/// with 60 three-seater rooms and 61 singles is two [RoomBlock]s. Floors are
/// not chosen by hand — [RoomPlan.build] gives each block whole floors of
/// its own, in order, so the building comes out seater-wise by floor (one
/// floor of singles, the next of three-seaters) without anyone having to
/// plan the floor numbers themselves. The common case (one room type) is
/// still just one block.
class RoomBlock {
  final int capacity;
  final int totalRooms;
  final int roomsPerFloor;
  final List<String> features;

  const RoomBlock({
    required this.capacity,
    required this.totalRooms,
    required this.roomsPerFloor,
    this.features = const [],
  });

  /// Whole floors needed, rounding up — the last floor of a block may come
  /// out short (61 rooms at 25/floor is 3 floors: 25, 25, 11).
  int get floorCount =>
      roomsPerFloor <= 0 ? 0 : (totalRooms / roomsPerFloor).ceil();

  int get totalBeds => totalRooms * capacity;
}

/// The blueprint the "add hostel" form fills in. Kept as a plain value object
/// so the preview in the UI and the actual write use the exact same maths —
/// what you see in the preview is literally what gets created.
class RoomPlan {
  final List<RoomBlock> blocks;

  const RoomPlan({this.blocks = const []});

  int get floors => blocks.fold(0, (acc, b) => acc + b.floorCount);
  int get totalRooms => blocks.fold(0, (acc, b) => acc + b.totalRooms);
  int get totalBeds => blocks.fold(0, (acc, b) => acc + b.totalBeds);

  /// Generates every room every block describes, in order.
  ///
  /// Floor-prefixed numbering: floor 1 -> 101, 102...; floor 2 -> 201...
  /// Blocks are laid out back to back — the first block claims floors
  /// starting at 1, the next block picks up on whatever floor the previous
  /// one left off, so two blocks never land on the same floor.
  List<Room> build() {
    final rooms = <Room>[];
    var floor = 1;
    for (final block in blocks) {
      var remaining = block.totalRooms;
      while (remaining > 0) {
        final onThisFloor = remaining < block.roomsPerFloor
            ? remaining
            : block.roomsPerFloor;
        for (var i = 1; i <= onThisFloor; i++) {
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
        remaining -= onThisFloor;
        floor++;
      }
    }
    return rooms;
  }

  /// Human summary for the confirmation line, e.g.
  /// "Floors 1–2: 60 rooms (3 Seater), Floors 3–5: 61 rooms (Single)".
  String get rangeSummary {
    var floor = 1;
    final parts = <String>[];
    for (final block in blocks) {
      if (block.totalRooms <= 0 || block.roomsPerFloor <= 0) continue;
      final startFloor = floor;
      floor += block.floorCount;
      final endFloor = floor - 1;
      final label = block.capacity == 1 ? 'Single' : '${block.capacity} Seater';
      final where = startFloor == endFloor
          ? 'Floor $startFloor'
          : 'Floors $startFloor–$endFloor';
      parts.add('$where: ${block.totalRooms} rooms ($label)');
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}

/// How many people belong to a hostel, split by whether they hold a bed.
///
/// Hostel membership and bed occupancy are separate facts in this app, and
/// conflating them under-reports badly. A CSV import can name a hostel
/// without a room — `AllotmentService.assignHostelOnly` writes `hostelId` and
/// nothing else — so a hostel can hold 2,400 students while `occupiedBeds`,
/// which only ever counts rooms, still reads zero.
///
/// Counted from the roster the app already watches rather than denormalised
/// onto the hostel document. `occupiedBeds` is denormalised because it is
/// written inside the allotment transaction that owns it; membership has no
/// such single writer (an import, a hostel-only assignment and a user edit
/// can all set `hostelId`), so a stored counter would drift.
class HostelHeadcount {
  /// Everyone whose `hostelId` is this hostel, bed or no bed.
  final int total;

  /// Of those, the ones who also hold a room.
  final int withBed;

  const HostelHeadcount({this.total = 0, this.withBed = 0});

  /// In the hostel, still waiting for a room.
  int get awaitingRoom => (total - withBed).clamp(0, total);

  /// Tallies every hostel in one pass over [users].
  ///
  /// Deactivated accounts are excluded — they cannot be allotted and counting
  /// them would make a hostel look fuller than it can be filled. Returns an
  /// entry only for hostels that actually have members; callers should treat
  /// a missing key as an empty count.
  static Map<String, HostelHeadcount> byHostel(Iterable<AppUser> users) {
    final total = <String, int>{};
    final withBed = <String, int>{};

    for (final u in users) {
      final id = u.hostelId;
      if (id == null || id.isEmpty || !u.isActive) continue;
      total[id] = (total[id] ?? 0) + 1;
      if (u.isAllotted) withBed[id] = (withBed[id] ?? 0) + 1;
    }

    return {
      for (final id in total.keys)
        id: HostelHeadcount(total: total[id]!, withBed: withBed[id] ?? 0),
    };
  }
}
