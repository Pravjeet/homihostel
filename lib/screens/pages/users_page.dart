import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_role.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import 'user_detail_dialog.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  String _query = '';
  String _roleFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;

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
            final filtered = all.where((u) {
              final q = _query.toLowerCase();
              final matchesQuery =
                  q.isEmpty ||
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q);
              final matchesRole =
                  _roleFilter == 'All' || u.displayRole == _roleFilter;
              return matchesQuery && matchesRole;
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
                        trailing: session.can(Perm.usersCreate)
                            ? ElevatedButton.icon(
                                onPressed: assignable.isEmpty
                                    ? null
                                    : () => _openCreateDialog(assignable),
                                icon: const Icon(Icons.person_add_alt_1, size: 18),
                                label: const Text('Add user'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      if (session.can(Perm.usersCreate) && assignable.isEmpty)
                        const Padding(
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
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                hintText: 'Search by name or email',
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (filtered.isEmpty)
                  const AppCard(
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
                          ),
                          if (i != filtered.length - 1)
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

  const _UserRow({
    required this.user,
    required this.roles,
    required this.isSelf,
  });

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    // Nobody may edit the Super Admin, and nobody may edit themselves into
    // a corner — both guarded here and in the Firestore rules.
    final editable =
        session.can(Perm.usersEdit) && !user.isSuperAdmin && !isSelf;

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => UserDetailDialog(user: user),
      ),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              user.initials,
              style: const TextStyle(
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
                      const Padding(
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
                  user.email,
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
              child: user.roleId == null && !user.isSuperAdmin
                  ? const StatusPill(
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
            const StatusPill(
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
                  const PopupMenuItem(
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
                style: const TextStyle(
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
        child: const Text(
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
        email: _email.text,
        password: _password.text,
        collegeId: widget.collegeId,
        roleId: _role!.id,
        roleName: _role!.name,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        gender: _gender,
        enrollmentNo: _enrollment.text.trim().isEmpty
            ? null
            : _enrollment.text.trim(),
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
                      style: const TextStyle(
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
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Email is required';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
                      return 'Enter a valid email address';
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
