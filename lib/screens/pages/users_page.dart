import 'package:flutter/material.dart';

import '../../core/identity.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_role.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import '../../services/hostel_service.dart';
import 'bulk_delete_users_dialog.dart';
import 'import_students_dialog.dart';
import 'user_detail_view.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

/// Deletes everyone the current filter is showing.
///
/// Scoped to the filtered list rather than "all students" on purpose: roles
/// are user-created data, so hard-coding a role name here would break the
/// moment someone renames Student or invents a second resident role. Filter
/// the list to what you want gone, then delete what you can see.
class _BulkDeleteButton extends StatelessWidget {
  final List<AppUser> targets;
  final String scopeLabel;
  final ValueChanged<List<AppUser>> onConfirm;

  const _BulkDeleteButton({
    required this.targets,
    required this.scopeLabel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final n = targets.length;
    return Tooltip(
      message: n == 0
          ? 'Nothing to delete in the current filter'
          : 'Deletes the $n user(s) currently listed ($scopeLabel).\n'
                'Super Admins and your own account are never included.',
      child: OutlinedButton.icon(
        onPressed: n == 0 ? null : () => onConfirm(targets),
        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
        label: Text('Delete $n shown'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: BorderSide(color: AppColors.dangerSoft),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}

class _UsersPageState extends State<UsersPage> {
  String _query = '';
  String _roleFilter = 'All';

  /// Null = any. `_kUnallotted` is a real choice, not a missing one — finding
  /// who still needs a bed is the reason someone opens this filter.
  String? _hostelFilter;
  String? _roomFilter;

  static const _kUnallotted = '__none__';

  /// Owned so "Clear filters" can actually empty the box. Without a
  /// controller, resetting `_query` in setState leaves the typed text on
  /// screen while the list silently shows everything.
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Cached so the import dialog can resolve hostel names to allot rooms.
  List<Hostel> _hostels = const [];

  /// Set when a row is tapped. Held as state rather than pushed as a route so
  /// the dashboard sidebar stays visible on the detail screen.
  AppUser? _openUser;

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;

    if (_openUser != null) {
      return UserDetailView(
        uid: _openUser!.uid,
        initial: _openUser!,
        onBack: () => setState(() => _openUser = null),
      );
    }

    return StreamBuilder<List<Hostel>>(
      stream: HostelService.instance.watchHostels(collegeId),
      builder: (context, hSnap) {
        _hostels = hSnap.data ?? const <Hostel>[];
        return StreamBuilder<List<AppRole>>(
      stream: DataService.instance.watchRoles(collegeId),
      builder: (context, roleSnap) {
        final roles = roleSnap.data ?? const <AppRole>[];
        final assignable = roles.where((r) => !r.isSystem).toList();

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

            final all = userSnap.data!;

            // Room numbers offered are those in the chosen hostel only —
            // "Room 101" exists in every block, so an unscoped room list
            // would match people across four buildings at once.
            final roomOptions =
                all
                    .where(
                      (u) =>
                          _hostelFilter == null ||
                          _hostelFilter == _kUnallotted ||
                          u.hostelName == _hostelFilter,
                    )
                    .map((u) => u.roomNumber)
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort((a, b) {
                    final na = int.tryParse(a);
                    final nb = int.tryParse(b);
                    if (na != null && nb != null) return na.compareTo(nb);
                    return a.compareTo(b);
                  });

            final filtered = all.where((u) {
              final q = _query.toLowerCase();
              final matchesQuery =
                  q.isEmpty ||
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q) ||
                  (u.enrollmentNo ?? '').toLowerCase().contains(q);
              final matchesRole =
                  _roleFilter == 'All' || u.displayRole == _roleFilter;
              final matchesHostel = switch (_hostelFilter) {
                null => true,
                _kUnallotted => !u.isAllotted,
                final h => u.hostelName == h,
              };
              final matchesRoom =
                  _roomFilter == null || u.roomNumber == _roomFilter;
              return matchesQuery && matchesRole && matchesHostel && matchesRoom;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        'Users  (${all.length})',
                        trailing: (session.can(Perm.usersCreate) ||
                                session.can(Perm.usersDelete))
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (session.can(Perm.usersDelete)) ...[
                                    _BulkDeleteButton(
                                      // Anything the current filter is
                                      // showing, minus the people who must
                                      // never be swept up in a bulk action.
                                      targets: filtered
                                          .where((u) => !u.isSuperAdmin)
                                          .where(
                                            (u) => u.uid != session.user.uid,
                                          )
                                          .toList(),
                                      scopeLabel: _scopeLabel,
                                      onConfirm: _openBulkDelete,
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                  if (session.can(Perm.usersCreate)) ...[
                                    OutlinedButton.icon(
                                      onPressed: assignable.isEmpty
                                          ? null
                                          : () =>
                                                _openImportDialog(all, roles),
                                      icon: const Icon(
                                        Icons.upload_file_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Import CSV'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: assignable.isEmpty
                                          ? null
                                          : () =>
                                                _openCreateDialog(assignable),
                                      icon: const Icon(
                                        Icons.person_add_alt_1,
                                        size: 18,
                                      ),
                                      label: const Text('Add user'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : null,
                      ),
                      if (session.can(Perm.usersCreate) && assignable.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Create at least one role before adding users — '
                            'a user without a role can\'t see anything.',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                hintText: 'Search by name, registration number or email',
                                prefixIcon: Icon(Icons.search_rounded),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Builder(
                            builder: (context) {
                              final options = <String>[
                                'All',
                                'Super Admin',
                                ...assignable.map((r) => r.name),
                                'Unassigned',
                              ];
                              // If the selected role was just deleted, fall
                              // back to 'All' rather than crashing the dropdown.
                              final value = options.contains(_roleFilter)
                                  ? _roleFilter
                                  : 'All';
                              return DropdownButton<String>(
                                value: value,
                                underline: const SizedBox.shrink(),
                                items: options
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r,
                                        child: Text(r),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _roleFilter = v ?? 'All'),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: _hostelFilter,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Hostel',
                                isDense: true,
                              ),
                              hint: const Text('Any hostel'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Any hostel'),
                                ),
                                const DropdownMenuItem<String>(
                                  value: _kUnallotted,
                                  child: Text('Not allotted'),
                                ),
                                ..._hostels.map(
                                  (h) => DropdownMenuItem(
                                    value: h.name,
                                    child: Text(
                                      h.code.isEmpty
                                          ? h.name
                                          : '${h.code} · ${h.name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              // Clearing the room too: a room number from the
                              // old hostel almost certainly matches nobody in
                              // the new one, leaving an empty list that looks
                              // like a bug.
                              onChanged: (v) => setState(() {
                                _hostelFilter = v;
                                _roomFilter = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              initialValue: roomOptions.contains(_roomFilter)
                                  ? _roomFilter
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Room',
                                isDense: true,
                              ),
                              hint: const Text('Any room'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('Any room'),
                                ),
                                ...roomOptions.map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(r),
                                  ),
                                ),
                              ],
                              onChanged: _hostelFilter == _kUnallotted
                                  ? null
                                  : (v) => setState(() => _roomFilter = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${filtered.length} of ${all.length}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const Spacer(),
                          if (_hostelFilter != null ||
                              _roomFilter != null ||
                              _roleFilter != 'All' ||
                              _query.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                _search.clear();
                                setState(() {
                                  _hostelFilter = null;
                                  _roomFilter = null;
                                  _roleFilter = 'All';
                                  _query = '';
                                });
                              },
                              icon: const Icon(
                                Icons.filter_alt_off_rounded,
                                size: 17,
                              ),
                              label: const Text('Clear filters'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (filtered.isEmpty)
                  AppCard(
                    padding: EdgeInsets.symmetric(vertical: 50),
                    child: Center(
                      child: Text(
                        'No users match your filters.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  )
                else
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          _UserRow(
                            user: filtered[i],
                            roles: assignable,
                            isSelf: filtered[i].uid == session.user.uid,
                            onOpen: () =>
                                setState(() => _openUser = filtered[i]),
                          ),
                          if (i != filtered.length - 1)
                            Divider(
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
      },
    );
  }

  /// Human description of what the list is currently filtered to, echoed in
  /// the delete confirmation so you can see whether this is the batch you
  /// meant before you wipe it.
  String get _scopeLabel {
    final parts = <String>[
      if (_roleFilter != 'All') 'role "$_roleFilter"' else 'all roles',
      if (_query.trim().isNotEmpty) 'search "${_query.trim()}"',
    ];
    return parts.join(' · ');
  }

  Future<void> _openBulkDelete(List<AppUser> targets) async {
    final collegeId = Session.of(context).user.collegeId;
    final messenger = ScaffoldMessenger.of(context);

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkDeleteUsersDialog(
        collegeId: collegeId,
        users: targets,
        scopeLabel: _scopeLabel,
      ),
    );

    if (done == true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Users deleted')),
      );
    }
  }

  Future<void> _openImportDialog(
    List<AppUser> existing,
    List<AppRole> roles,
  ) async {
    // Read the session HERE, from the page's context — inside the builder the
    // context belongs to the dialog's route, which sits above SessionScope.
    final collegeId = Session.of(context).user.collegeId;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportStudentsDialog(
        collegeId: collegeId,
        existingUsers: existing,
        roles: roles,
        hostels: _hostels,
      ),
    );
  }

  Future<void> _openCreateDialog(List<AppRole> roles) async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateUserDialog(
        collegeId: Session.of(context).user.collegeId,
        roles: roles,
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created')),
      );
    }
  }
}

class _UserRow extends StatelessWidget {
  final AppUser user;
  final List<AppRole> roles;
  final bool isSelf;
  final VoidCallback onOpen;

  const _UserRow({
    required this.user,
    required this.roles,
    required this.isSelf,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    // Nobody may edit the Super Admin, and nobody may edit themselves into
    // a corner — both guarded here and in the Firestore rules.
    final editable =
        session.can(Perm.usersEdit) && !user.isSuperAdmin && !isSelf;

    return InkWell(
      onTap: onOpen,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              user.initials,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (isSelf)
                      Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: StatusPill(
                          'YOU',
                          AppColors.info,
                          AppColors.infoSoft,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  Identity.display(user.email),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
              child: user.roleId == null && !user.isSuperAdmin
                  ? StatusPill(
                      'NO ROLE',
                      AppColors.warning,
                      AppColors.warningSoft,
                    )
                  : StatusPill(
                      user.displayRole.toUpperCase(),
                      AppColors.primary,
                      AppColors.primarySoft,
                    ),
            ),
          ),
          if (!user.isActive)
            StatusPill(
              'DEACTIVATED',
              AppColors.danger,
              AppColors.dangerSoft,
            ),
          const SizedBox(width: 8),
          if (editable)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) => _handle(context, v),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'role',
                  child: Text('Change role'),
                ),
                PopupMenuItem(
                  value: 'active',
                  child: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
                ),
                if (session.can(Perm.usersDelete))
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'Delete profile',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
              ],
            )
          else
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(BuildContext context, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case 'role':
          final picked = await showDialog<AppRole?>(
            context: context,
            builder: (_) => _RolePickerDialog(roles: roles, current: user.roleId),
          );
          if (picked != null) {
            await DataService.instance.setUserRole(
              user.uid,
              picked.id == '__none__' ? null : picked,
            );
            messenger.showSnackBar(
              const SnackBar(content: Text('Role updated')),
            );
          }
          break;
        case 'active':
          await DataService.instance.setUserActive(user.uid, !user.isActive);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                user.isActive ? 'User deactivated' : 'User reactivated',
              ),
            ),
          );
          break;
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('Delete ${user.name}?'),
              content: const Text(
                'This removes their profile and access immediately.\n\n'
                'Note: their sign-in account itself can only be removed from '
                'the Firebase console (or a Cloud Function). Deactivating is '
                'usually the safer choice.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await DataService.instance.deleteUserProfile(user.uid);
            messenger.showSnackBar(
              const SnackBar(content: Text('Profile deleted')),
            );
          }
          break;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.describeError(e))),
      );
    }
  }
}

class _RolePickerDialog extends StatelessWidget {
  final List<AppRole> roles;
  final String? current;
  const _RolePickerDialog({required this.roles, required this.current});

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Assign role'),
    children: [
      for (final r in roles)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, r),
          child: Row(
            children: [
              Icon(
                r.id == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 19,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Text(r.name),
              const Spacer(),
              Text(
                '${r.permissions.length}',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      const Divider(),
      SimpleDialogOption(
        onPressed: () =>
            Navigator.pop(context, const AppRole(id: '__none__', name: '')),
        child: Text(
          'Remove role',
          style: TextStyle(color: AppColors.danger),
        ),
      ),
    ],
  );
}

class _CreateUserDialog extends StatefulWidget {
  final String collegeId;
  final List<AppRole> roles;
  const _CreateUserDialog({required this.collegeId, required this.roles});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _enrollment = TextEditingController();

  AppRole? _role;
  String? _gender;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = widget.roles.isNotEmpty ? widget.roles.first : null;
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone, _enrollment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _role == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.createSubUser(
        name: _name.text,
        email: Identity.toAuthEmail(_email.text),
        // When they typed a registration number, that IS the enrollment no.
        enrollmentNo: Identity.looksLikeEmail(_email.text.trim())
            ? (_enrollment.text.trim().isEmpty ? null : _enrollment.text.trim())
            : _email.text.trim(),
        password: _password.text,
        collegeId: widget.collegeId,
        roleId: _role!.id,
        roleName: _role!.name,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        gender: _gender,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a user'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Registration number or email',
                    helperText:
                        'Students can use just a registration number — no '
                        'inbox needed.',
                  ),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) {
                      return 'A registration number or email is required';
                    }
                    if (Identity.looksLikeEmail(s)) {
                      if (!RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(s)) {
                        return 'Enter a valid email address';
                      }
                    } else if (!Identity.isValidRegistrationNumber(s)) {
                      return 'Use letters, digits, . _ or - only';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'Share this with them; they can reset it later.',
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? 'Use at least 6 characters'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<AppRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: widget.roles
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                      )
                      .toList(),
                  onChanged: _busy ? null : (v) => setState(() => _role = v),
                  validator: (v) => v == null ? 'Pick a role' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        enabled: !_busy,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone (optional)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _gender,
                        decoration: const InputDecoration(
                          labelText: 'Gender (optional)',
                        ),
                        items: const ['Male', 'Female', 'Other']
                            .map(
                              (g) =>
                                  DropdownMenuItem(value: g, child: Text(g)),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _gender = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _enrollment,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Enrollment / Employee no. (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create user'),
        ),
      ],
    );
  }
}
