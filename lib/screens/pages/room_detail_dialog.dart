import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/allotment_service.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';

/// Who is in one room, and a way to fill its free beds.
///
/// Occupancy is read from the roster (`hostelId` + `roomId` on each student)
/// rather than from the room's own `occupantUids`. Both are written by the
/// same allotment transaction so they agree, but the roster carries the names
/// and registration numbers this dialog needs anyway — deriving from it means
/// one pooled stream instead of a second read, and the list updates the
/// instant an allotment lands.
///
/// Allotting here goes through [AllotmentService.allot], the same call Room
/// Allotment makes. That is the whole point: the room's `occupantUids`, the
/// student's `roomId` and the hostel's `occupiedBeds` counter all move inside
/// one transaction, so a bed filled from this dialog shows up everywhere —
/// the hostel card, the fees roster, the student's profile — with no extra
/// bookkeeping here.
/// Permissions are passed in rather than read from the context: a dialog is
/// pushed onto the root Navigator, so its context sits above SessionScope and
/// `Session.of` would throw. See the note on [BulkDeleteUsersDialog].
class RoomDetailDialog extends StatefulWidget {
  final String collegeId;
  final Hostel hostel;
  final Room room;

  /// `allotment.manage` — whether the free-bed picker is offered.
  final bool canAllot;

  /// `users.view` — whether the roster may be listed at all. Without it the
  /// occupants can't be shown, and the query would be rejected by the rules.
  final bool canSeeRoster;

  /// Opens the room editor. Null when the viewer can't manage hostels, which
  /// hides the button rather than showing one that fails.
  final VoidCallback? onEditRoom;

  const RoomDetailDialog({
    super.key,
    required this.collegeId,
    required this.hostel,
    required this.room,
    required this.canAllot,
    required this.canSeeRoster,
    this.onEditRoom,
  });

  @override
  State<RoomDetailDialog> createState() => _RoomDetailDialogState();
}

class _RoomDetailDialogState extends State<RoomDetailDialog> {
  final _search = TextEditingController();
  String _query = '';

  /// True once the warden has asked to add someone, so the picker (and the
  /// roster search it implies) stays out of the way until wanted.
  bool _picking = false;

  bool _busy = false;
  String? _error;

  /// Rendering every candidate is what made other screens crawl — a campus
  /// with thousands awaiting a room would build thousands of rows here.
  static const _maxCandidates = 25;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Empties one bed.
  ///
  /// Removes the student from the room *and* the hostel, which is what
  /// `vacate` does. There is deliberately no "free the bed but stay in the
  /// hostel" variant: a student is either allotted a hostel and room together
  /// or is waiting in Room Allotment to be given both, and a half-state of
  /// hostel-without-room is exactly what this app no longer tracks.
  Future<void> _removeOccupant(AppUser student) async {
    final hostelName = widget.hostel.name;
    // Captured before the confirm dialog: reading it afterwards would be
    // reaching through a context that may no longer be mounted.
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Move ${student.name} out of room ${widget.room.number}?'),
        content: Text(
          '${student.name} leaves $hostelName and the bed is freed. They will '
          'appear in Room Allotment as awaiting a room, where you can give '
          'them a new hostel and room together.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Move out'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AllotmentService.instance.vacate(
        collegeId: widget.collegeId,
        student: student,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('${student.name} moved out of $hostelName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.describeError(e);
      });
    }
  }

  /// Empties the room in one go.
  ///
  /// Sequential, not parallel — each call is a transaction on the same room
  /// and hostel document, so firing them together would just make them retry
  /// against each other.
  Future<void> _emptyRoom(List<AppUser> occupants) async {
    final n = occupants.length;
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Empty room ${widget.room.number}?'),
        content: Text(
          'All $n student${n == 1 ? '' : 's'} leave ${widget.hostel.name} and '
          'the beds are freed. They will appear in Room Allotment awaiting a '
          'room, where you can give each a new hostel and room together.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: Text('Move out $n student${n == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    var freed = 0;
    final failures = <String>[];
    for (final student in occupants) {
      try {
        await AllotmentService.instance.vacate(
          collegeId: widget.collegeId,
          student: student,
        );
        freed++;
      } catch (e) {
        // One student failing shouldn't abandon the rest — report at the end.
        failures.add('${student.name}: ${AuthService.describeError(e)}');
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failures.isEmpty ? null : failures.join('\n');
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Moved out $freed student${freed == 1 ? '' : 's'} from room '
          '${widget.room.number}'
          '${failures.isEmpty ? '' : ' — ${failures.length} could not be done'}',
        ),
      ),
    );
  }

  Future<void> _allot(AppUser student) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AllotmentService.instance.allot(
        collegeId: widget.collegeId,
        student: student,
        hostel: widget.hostel,
        room: widget.room,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Collapse the picker and clear the search: the common case is one
        // student at a time, and leaving a stale query up implies the next
        // person is already filtered for.
        _picking = false;
        _query = '';
        _search.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('${student.name} allotted room ${widget.room.number}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // The service re-checks capacity, gender and prior allotment inside its
      // transaction, so its message is the accurate one — show it verbatim
      // instead of guessing why it refused.
      setState(() {
        _busy = false;
        _error = AuthService.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAllot = widget.canAllot;
    final canSeeRoster = widget.canSeeRoster;
    final room = widget.room;

    return AlertDialog(
      title: Text('Room ${room.number}'),
      content: SizedBox(
        width: 470,
        child: StreamBuilder<List<AppUser>>(
          stream: canSeeRoster
              ? DataService.instance.watchUsers(widget.collegeId)
              : const Stream<List<AppUser>>.empty(),
          builder: (context, snap) {
            final roster = snap.data ?? const <AppUser>[];

            final occupants =
                roster
                    .where(
                      (u) =>
                          u.hostelId == widget.hostel.id &&
                          u.roomId == room.id &&
                          u.isActive,
                    )
                    .toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

            // Beds free according to the roster. `room.capacity` is a snapshot
            // from when the dialog opened, which is fine — capacity only
            // changes when someone edits the room.
            final free = (room.capacity - occupants.length).clamp(
              0,
              room.capacity,
            );

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    _Banner(_error!, AppColors.danger, AppColors.dangerSoft),
                    const SizedBox(height: 16),
                  ],

                  _RoomFacts(room: room, occupied: occupants.length),
                  const SizedBox(height: 18),

                  if (!canSeeRoster)
                    Text(
                      'You don\'t have permission to see who lives here.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    )
                  else if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _OccupantList(
                      occupants: occupants,
                      busy: _busy,
                      // Emptying a bed is the same authority as filling one.
                      onRemove: canAllot ? _removeOccupant : null,
                      onEmptyRoom: canAllot
                          ? () => _emptyRoom(occupants)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (room.status != RoomStatus.active)
                      _Banner(
                        'This room is marked ${room.status.label}, so it '
                        'can\'t take students until that changes.',
                        AppColors.warning,
                        AppColors.warningSoft,
                      )
                    else if (free == 0)
                      Text(
                        'All ${room.capacity} beds are taken.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      )
                    else if (!canAllot)
                      Text(
                        '$free bed${free == 1 ? '' : 's'} free. You don\'t '
                        'have permission to allot students.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      )
                    else if (!_picking)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: () => setState(() => _picking = true),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: Text(
                            'Allot a student  ($free bed'
                            '${free == 1 ? '' : 's'} free)',
                          ),
                        ),
                      )
                    else
                      _Picker(
                        hostel: widget.hostel,
                        roster: roster,
                        controller: _search,
                        query: _query,
                        busy: _busy,
                        maxShown: _maxCandidates,
                        onQuery: (v) => setState(() => _query = v),
                        onCancel: () => setState(() {
                          _picking = false;
                          _query = '';
                          _search.clear();
                        }),
                        onPick: _allot,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (widget.onEditRoom != null)
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onEditRoom!();
                  },
            child: const Text('Edit room'),
          ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ------------------------------- room facts -------------------------------

class _RoomFacts extends StatelessWidget {
  final Room room;
  final int occupied;

  const _RoomFacts({required this.room, required this.occupied});

  @override
  Widget build(BuildContext context) {
    final free = (room.capacity - occupied).clamp(0, room.capacity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              _Fact('Beds', '$occupied / ${room.capacity}'),
              _Fact('Free', '$free'),
              _Fact('Type', room.capacityLabel),
              _Fact('Floor', '${room.floor}'),
              _Fact('Status', room.status.label),
            ],
          ),
          if (room.features.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              room.features.join('  ·  '),
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
          if ((room.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              room.note!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;
  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textMuted,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

// ------------------------------- occupants -------------------------------

class _OccupantList extends StatelessWidget {
  final List<AppUser> occupants;

  /// Null when the viewer can't allot, which hides the remove action rather
  /// than offering one that would be refused.
  final ValueChanged<AppUser>? onRemove;

  final VoidCallback? onEmptyRoom;
  final bool busy;

  const _OccupantList({
    required this.occupants,
    this.onRemove,
    this.onEmptyRoom,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    if (occupants.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: AppColors.successSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            'Empty — nobody is in this room yet.',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Residents (${occupants.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Only worth offering for more than one — a single resident is
            // quicker to remove from their own row.
            if (onEmptyRoom != null && occupants.length > 1)
              TextButton.icon(
                onPressed: busy ? null : onEmptyRoom,
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Empty room'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < occupants.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.border),
          _OccupantRow(student: occupants[i], onRemove: onRemove, busy: busy),
        ],
      ],
    );
  }
}

class _OccupantRow extends StatelessWidget {
  final AppUser student;
  final ValueChanged<AppUser>? onRemove;
  final bool busy;

  const _OccupantRow({required this.student, this.onRemove, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final u = student;
    final detail = [
      if ((u.enrollmentNo ?? '').isNotEmpty) u.enrollmentNo!,
      if ((u.trade ?? '').isNotEmpty) u.trade!,
      if ((u.year ?? '').isNotEmpty) u.year!,
      if (u.sem != null) 'Sem ${u.sem}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              u.initials,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((u.phone ?? '').isNotEmpty)
            Text(
              u.phone!,
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: busy ? null : () => onRemove!(u),
              icon: Icon(
                Icons.person_remove_outlined,
                size: 18,
                color: AppColors.danger,
              ),
              tooltip: 'Move out of this room',
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------- picker --------------------------------

/// Chooses a student for a free bed.
///
/// Students already recorded as living in this hostel but with no room yet
/// come first: after a CSV import that is the overwhelming majority of who a
/// warden is looking for, and making them scroll past the whole institute to
/// find one is the difference between this being useful and being ignored.
class _Picker extends StatelessWidget {
  final Hostel hostel;
  final List<AppUser> roster;
  final TextEditingController controller;
  final String query;
  final bool busy;
  final int maxShown;
  final ValueChanged<String> onQuery;
  final VoidCallback onCancel;
  final ValueChanged<AppUser> onPick;

  const _Picker({
    required this.hostel,
    required this.roster,
    required this.controller,
    required this.query,
    required this.busy,
    required this.maxShown,
    required this.onQuery,
    required this.onCancel,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    // The eligibility rule and its ordering live on the service, so they can
    // be tested directly and stay consistent with what `allot` will accept.
    final eligible = AllotmentService.bedCandidates(
      hostel: hostel,
      roster: roster,
    );

    // Counted separately only to explain the omission: silently dropping the
    // students a Boys/Girls hostel can't take looks like a missing roster.
    final hiddenByGender = roster
        .where((u) => u.isActive && !u.isSuperAdmin && !u.isAllotted)
        .where((u) => !AllotmentService.genderAllows(hostel.gender, u.gender))
        .length;

    final q = query.trim().toLowerCase();
    final matched = q.isEmpty
        ? eligible
        : eligible
              .where(
                (u) =>
                    u.name.toLowerCase().contains(q) ||
                    (u.enrollmentNo ?? '').toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q),
              )
              .toList();

    final shown = matched.take(maxShown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Who is moving in?',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: true,
          enabled: !busy,
          onChanged: onQuery,
          decoration: const InputDecoration(
            hintText: 'Search name, registration number or email',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              eligible.isEmpty
                  ? 'Nobody is waiting for a room.'
                  : 'No unallotted student matches that search.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  _CandidateRow(
                    student: shown[i],
                    inThisHostel: shown[i].hostelId == hostel.id,
                    onTap: () => onPick(shown[i]),
                  ),
                ],
              ],
            ),
          ),
        if (matched.length > shown.length) ...[
          const SizedBox(height: 8),
          Text(
            'Showing $maxShown of ${matched.length} — keep typing to narrow it '
            'down.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
        if (hiddenByGender > 0) ...[
          const SizedBox(height: 6),
          Text(
            '$hiddenByGender student${hiddenByGender == 1 ? '' : 's'} not '
            'shown — this is a ${hostel.gender.label} hostel.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final AppUser student;
  final bool inThisHostel;
  final VoidCallback onTap;

  const _CandidateRow({
    required this.student,
    required this.inThisHostel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final u = student;
    final detail = [
      if ((u.enrollmentNo ?? '').isNotEmpty) u.enrollmentNo!,
      if ((u.trade ?? '').isNotEmpty) u.trade!,
      if (u.sem != null) 'Sem ${u.sem}',
    ].join('  ·  ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          u.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (inThisHostel) ...[
                        const SizedBox(width: 8),
                        StatusPill(
                          'IN THIS HOSTEL',
                          AppColors.primary,
                          AppColors.primarySoft,
                        ),
                      ],
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.add_circle_outline, size: 19, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// -------------------------------- banner --------------------------------

class _Banner extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;

  const _Banner(this.text, this.fg, this.bg);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, height: 1.4)),
  );
}
