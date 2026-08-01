import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/allotment_service.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import '../../services/hostel_service.dart';
import 'allot_room_dialog.dart';
import 'user_detail_dialog.dart';

/// Room Allotment: who has a bed, who doesn't, and the actions to fix that.
class AllotmentPage extends StatefulWidget {
  const AllotmentPage({super.key});

  @override
  State<AllotmentPage> createState() => _AllotmentPageState();
}

class _AllotmentPageState extends State<AllotmentPage> {
  String _query = '';
  _Filter _filter = _Filter.pending;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;
    final canAllot = session.can(Perm.allotmentManage);

    return StreamBuilder<List<Hostel>>(
      stream: HostelService.instance.watchHostels(collegeId),
      builder: (context, hostelSnap) {
        final hostels = hostelSnap.data ?? const <Hostel>[];

        return StreamBuilder<List<AppUser>>(
          stream: DataService.instance.watchUsers(collegeId),
          builder: (context, userSnap) {
            if (userSnap.hasError) {
              return AppCard(
                child: Text(AuthService.describeError(userSnap.error!)),
              );
            }
            if (!userSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            // The Super Admin is staff, not a resident — exclude from the
            // allotment worklist so it isn't cluttered.
            final people = userSnap.data!
                .where((u) => !u.isSuperAdmin)
                .toList();
            final allotted = people.where((u) => u.isAllotted).toList();
            final pending = people.where((u) => !u.isAllotted).toList();

            final totalBeds = hostels.fold<int>(0, (s, h) => s + h.bedCount);
            final freeBeds = hostels.fold<int>(0, (s, h) => s + h.freeBeds);

            final source = switch (_filter) {
              _Filter.pending => pending,
              _Filter.allotted => allotted,
              _Filter.all => people,
            };
            final q = _query.trim().toLowerCase();
            final shown = q.isEmpty
                ? source
                : source
                      .where(
                        (u) =>
                            u.name.toLowerCase().contains(q) ||
                            u.email.toLowerCase().contains(q) ||
                            (u.enrollmentNo ?? '').toLowerCase().contains(q) ||
                            (u.roomNumber ?? '').toLowerCase().contains(q),
                      )
                      .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('Room allotment'),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 30,
                        runSpacing: 14,
                        children: [
                          _Metric('Awaiting a room', '${pending.length}',
                              pending.isEmpty
                                  ? AppColors.success
                                  : AppColors.warning),
                          _Metric('Allotted', '${allotted.length}',
                              AppColors.primary),
                          _Metric('Free beds', '$freeBeds',
                              freeBeds == 0
                                  ? AppColors.danger
                                  : AppColors.success),
                          _Metric('Total beds', '$totalBeds',
                              AppColors.textStrong),
                        ],
                      ),
                      if (hostels.isEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'No hostels exist yet — create one under '
                          '"Hostels & Rooms" before allotting.',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (pending.isNotEmpty && freeBeds == 0) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Every bed is taken but people are still waiting. '
                          'Add rooms or a floor to make space.',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                hintText:
                                    'Search name, email, enrollment or room',
                                prefixIcon: Icon(Icons.search_rounded),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          SegmentedButton<_Filter>(
                            segments: [
                              ButtonSegment(
                                value: _Filter.pending,
                                label: Text('Pending (${pending.length})'),
                              ),
                              ButtonSegment(
                                value: _Filter.allotted,
                                label: Text('Allotted (${allotted.length})'),
                              ),
                              const ButtonSegment(
                                value: _Filter.all,
                                label: Text('All'),
                              ),
                            ],
                            selected: {_filter},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) =>
                                setState(() => _filter = s.first),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (shown.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 54),
                    child: Center(
                      child: Text(
                        _filter == _Filter.pending
                            ? 'Everyone has a room. Nice.'
                            : 'Nobody matches that search.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  )
                else
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          _PersonRow(
                            person: shown[i],
                            canAllot: canAllot,
                            onOpen: () => _openDetail(shown[i]),
                            onAllot: () => _openAllot(shown[i], move: false),
                            onMove: () => _openAllot(shown[i], move: true),
                            onVacate: () => _vacate(shown[i]),
                          ),
                          if (i != shown.length - 1)
                            const Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                              color: AppColors.border,
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openDetail(AppUser u) => showDialog(
    context: context,
    builder: (_) => UserDetailDialog(user: u),
  );

  Future<void> _openAllot(AppUser u, {required bool move}) => showDialog(
    context: context,
    builder: (_) => AllotRoomDialog(student: u, isMove: move),
  );

  Future<void> _vacate(AppUser u) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Vacate ${u.roomLabel}?'),
        content: Text('${u.name} will be removed and the bed freed up.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Vacate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await AllotmentService.instance.vacate(
        collegeId: u.collegeId,
        student: u,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Room vacated')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AllotmentFailure ? e.message : AuthService.describeError(e),
          ),
        ),
      );
    }
  }
}

enum _Filter { pending, allotted, all }

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );
}

class _PersonRow extends StatelessWidget {
  final AppUser person;
  final bool canAllot;
  final VoidCallback onOpen;
  final VoidCallback onAllot;
  final VoidCallback onMove;
  final VoidCallback onVacate;

  const _PersonRow({
    required this.person,
    required this.canAllot,
    required this.onOpen,
    required this.onAllot,
    required this.onMove,
    required this.onVacate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                person.initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      person.displayRole,
                      if (person.enrollmentNo != null) person.enrollmentNo!,
                      if (person.gender != null) person.gender!,
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: person.isAllotted
                    ? StatusPill(
                        person.roomLabel!.toUpperCase(),
                        AppColors.success,
                        AppColors.successSoft,
                      )
                    : const StatusPill(
                        'NO ROOM',
                        AppColors.warning,
                        AppColors.warningSoft,
                      ),
              ),
            ),
            if (canAllot)
              person.isAllotted
                  ? PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, size: 20),
                      onSelected: (v) =>
                          v == 'move' ? onMove() : onVacate(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'move',
                          child: Text('Change room'),
                        ),
                        PopupMenuItem(
                          value: 'vacate',
                          child: Text(
                            'Vacate',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ],
                    )
                  : FilledButton(
                      onPressed: onAllot,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Allot'),
                    )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
