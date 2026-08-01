import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/allotment_service.dart';
import '../../services/auth_service.dart';
import '../../services/hostel_service.dart';

/// Pick a hostel, then a free room, for one student.
///
/// Hostels the student is ineligible for (wrong gender) are shown but disabled
/// with the reason attached, rather than hidden — a warden looking for "why
/// isn't Block A listed?" should get an answer, not an absence.
class AllotRoomDialog extends StatefulWidget {
  final AppUser student;

  /// True when the student already has a room and we're relocating them.
  final bool isMove;

  const AllotRoomDialog({
    super.key,
    required this.student,
    this.isMove = false,
  });

  @override
  State<AllotRoomDialog> createState() => _AllotRoomDialogState();
}

class _AllotRoomDialogState extends State<AllotRoomDialog> {
  Hostel? _hostel;
  Room? _room;
  bool _onlyEmpty = false;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_hostel == null || _room == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.isMove) {
        await AllotmentService.instance.move(
          collegeId: widget.student.collegeId,
          student: widget.student,
          toHostel: _hostel!,
          toRoom: _room!,
        );
      } else {
        await AllotmentService.instance.allot(
          collegeId: widget.student.collegeId,
          student: widget.student,
          hostel: _hostel!,
          room: _room!,
        );
      }
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${widget.student.name} → ${_hostel!.name}, '
            'Room ${_room!.number}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AllotmentFailure
              ? e.message
              : AuthService.describeError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collegeId = Session.of(context).user.collegeId;
    final student = widget.student;

    return AlertDialog(
      title: Text(
        widget.isMove
            ? 'Move ${student.name}'
            : 'Allot a room to ${student.name}',
      ),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StudentStrip(student: student),
            const SizedBox(height: 14),

            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            Expanded(
              child: StreamBuilder<List<Hostel>>(
                stream: HostelService.instance.watchHostels(collegeId),
                builder: (context, hostelSnap) {
                  if (!hostelSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final hostels = hostelSnap.data!;
                  if (hostels.isEmpty) {
                    return const Center(
                      child: Text(
                        'No hostels exist yet. Create one first.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HOSTEL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: hostels.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final h = hostels[i];
                            final eligible = AllotmentService.genderAllows(
                              h.gender,
                              student.gender,
                            );
                            final selected = _hostel?.id == h.id;
                            return Tooltip(
                              message: eligible
                                  ? '${h.freeBeds} free of ${h.bedCount}'
                                  : '${h.gender.label} hostel — not eligible',
                              child: ChoiceChip(
                                label: Text(
                                  '${h.name}  (${h.freeBeds})',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: !eligible
                                        ? AppColors.textMuted
                                        : selected
                                        ? AppColors.primary
                                        : AppColors.textStrong,
                                  ),
                                ),
                                selected: selected,
                                onSelected: eligible && !_busy
                                    ? (_) => setState(() {
                                        _hostel = h;
                                        _room = null;
                                      })
                                    : null,
                                selectedColor: AppColors.primarySoft,
                                backgroundColor: Colors.white,
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_hostel == null)
                        const Expanded(
                          child: Center(
                            child: Text(
                              'Pick a hostel to see its free rooms.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: _RoomPicker(
                            collegeId: collegeId,
                            hostel: _hostel!,
                            selected: _room,
                            onlyEmpty: _onlyEmpty,
                            onToggleOnlyEmpty: (v) =>
                                setState(() => _onlyEmpty = v),
                            onPick: (r) => setState(() => _room = r),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_room == null || _busy) ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _room == null
                      ? 'Select a room'
                      : 'Allot Room ${_room!.number}',
                ),
        ),
      ],
    );
  }
}

class _StudentStrip extends StatelessWidget {
  final AppUser student;
  const _StudentStrip({required this.student});

  @override
  Widget build(BuildContext context) {
    final noGender = student.gender == null || student.gender!.trim().isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [
                student.displayRole,
                if (student.gender != null) student.gender!,
                if (student.enrollmentNo != null) student.enrollmentNo!,
                if (student.isAllotted) 'Currently in ${student.roomLabel}',
              ].join('  ·  '),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (noGender)
            const Tooltip(
              message:
                  'No gender on this profile, so Boys/Girls hostels can\'t be '
                  'checked. Set it on their detail screen.',
              child: Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomPicker extends StatelessWidget {
  final String collegeId;
  final Hostel hostel;
  final Room? selected;
  final bool onlyEmpty;
  final ValueChanged<bool> onToggleOnlyEmpty;
  final ValueChanged<Room> onPick;

  const _RoomPicker({
    required this.collegeId,
    required this.hostel,
    required this.selected,
    required this.onlyEmpty,
    required this.onToggleOnlyEmpty,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Room>>(
      stream: HostelService.instance.watchRooms(collegeId, hostel.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Only rooms that can actually take someone.
        var rooms = snap.data!.where((r) => r.isAvailable).toList();
        if (onlyEmpty) rooms = rooms.where((r) => r.occupied == 0).toList();

        final byFloor = <int, List<Room>>{};
        for (final r in rooms) {
          byFloor.putIfAbsent(r.floor, () => []).add(r);
        }
        final floors = byFloor.keys.toList()..sort();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'AVAILABLE ROOMS  (${rooms.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: AppColors.textMuted,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Empty rooms only',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                Switch(
                  value: onlyEmpty,
                  onChanged: onToggleOnlyEmpty,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: rooms.isEmpty
                  ? const Center(
                      child: Text(
                        'No free rooms match. Try another hostel, or turn off '
                        '"empty rooms only".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView(
                      children: floors.map((floor) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Floor $floor',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: byFloor[floor]!.map((r) {
                                final isSel = selected?.id == r.id;
                                return InkWell(
                                  onTap: () => onPick(r),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 96,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? AppColors.primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSel
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          r.number,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: isSel
                                                ? Colors.white
                                                : AppColors.textStrong,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${r.free} of ${r.capacity} free',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: isSel
                                                ? Colors.white70
                                                : AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}
