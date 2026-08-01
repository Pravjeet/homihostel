import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../services/data_service.dart';

/// The landing page. It renders the same for everyone, but each block is
/// permission-gated, so a Student sees their own summary while a Super Admin
/// sees institution-wide counts — from one widget tree.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.can(Perm.usersView))
          _InstitutionStats(collegeId: session.user.collegeId)
        else
          const _PersonalSummary(),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 3, child: _AccessCard()),
            const SizedBox(width: 20),
            const Expanded(flex: 2, child: _QuickActions()),
          ],
        ),
      ],
    );
  }
}

class _InstitutionStats extends StatelessWidget {
  final String collegeId;
  const _InstitutionStats({required this.collegeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: DataService.instance.watchUsers(collegeId),
      builder: (context, snap) {
        final users = snap.data ?? const <AppUser>[];
        final byRole = <String, int>{};
        for (final u in users) {
          byRole[u.displayRole] = (byRole[u.displayRole] ?? 0) + 1;
        }
        final unassigned = users.where((u) => u.roleId == null).length;
        final inactive = users.where((u) => !u.isActive).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth > 900
                    ? 4
                    : c.maxWidth > 560
                    ? 2
                    : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 2.5,
                  children: [
                    _StatTile(
                      label: 'Total users',
                      value: '${users.length}',
                      icon: Icons.group_rounded,
                      color: AppColors.primary,
                      background: AppColors.primarySoft,
                    ),
                    _StatTile(
                      label: 'Students',
                      value: '${byRole['Student'] ?? 0}',
                      icon: Icons.school_rounded,
                      color: AppColors.info,
                      background: AppColors.infoSoft,
                    ),
                    _StatTile(
                      label: 'Awaiting a role',
                      value: '$unassigned',
                      icon: Icons.hourglass_top_rounded,
                      color: AppColors.warning,
                      background: AppColors.warningSoft,
                    ),
                    _StatTile(
                      label: 'Deactivated',
                      value: '$inactive',
                      icon: Icons.block_rounded,
                      color: AppColors.danger,
                      background: AppColors.dangerSoft,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('People by role'),
                  const SizedBox(height: 16),
                  if (byRole.isEmpty)
                    const Text(
                      'No users yet.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  else
                    ...(byRole.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                        .map(
                          (e) => _RoleBar(
                            label: e.key,
                            count: e.value,
                            total: users.length,
                          ),
                        ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoleBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _RoleBar({
    required this.label,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count  (${(fraction * 100).round()}%)',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalSummary extends StatelessWidget {
  const _PersonalSummary();

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    return LayoutBuilder(
      builder: (context, c) => GridView.count(
        crossAxisCount: c.maxWidth > 800 ? 3 : 1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2.5,
        children: [
          _StatTile(
            label: 'Your role',
            value: session.user.displayRole,
            icon: Icons.badge_rounded,
            color: AppColors.primary,
            background: AppColors.primarySoft,
          ),
          const _StatTile(
            label: 'Open requests',
            value: '—',
            icon: Icons.inbox_rounded,
            color: AppColors.info,
            background: AppColors.infoSoft,
          ),
          const _StatTile(
            label: 'Pending dues',
            value: '—',
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.warning,
            background: AppColors.warningSoft,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Shows the user exactly what their role grants — useful for you while
/// developing, and reassuring for staff wondering why a menu is missing.
class _AccessCard extends StatelessWidget {
  const _AccessCard();

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final granted = session.user.isSuperAdmin
        ? Perm.all
        : (session.role?.permissions.toList() ?? []);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Your access',
            trailing: StatusPill(
              session.user.displayRole.toUpperCase(),
              AppColors.primary,
              AppColors.primarySoft,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${granted.length} permission${granted.length == 1 ? '' : 's'} '
            'granted to your role.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in Perm.catalogue.entries)
                if (entry.value.any((p) => granted.contains(p.key)))
                  StatusPill(
                    entry.key,
                    AppColors.success,
                    AppColors.successSoft,
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final actions = <String>[
      if (session.can(Perm.usersCreate)) 'Add a user',
      if (session.can(Perm.rolesManage)) 'Create a role',
      if (session.can(Perm.noticesManage)) 'Publish a notice',
      if (session.can(Perm.allotmentManage)) 'Allot a room',
      if (session.can(Perm.requestsCreate)) 'Raise a request',
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Quick actions'),
          const SizedBox(height: 14),
          if (actions.isEmpty)
            const Text(
              'Nothing available for your role yet.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            )
          else
            ...actions.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.arrow_right_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(a, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
