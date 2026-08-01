import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../services/allotment_service.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import 'allot_room_dialog.dart';

/// The full record for one person: everything that wasn't asked for at
/// account creation, plus their room.
///
/// Account creation deliberately stays minimal — name, email, password, role.
/// Everything else is optional detail you fill in when you have it, which is
/// what this screen is for.
class UserDetailDialog extends StatefulWidget {
  final AppUser user;
  const UserDetailDialog({super.key, required this.user});

  @override
  State<UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<UserDetailDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;

  String? _gender;
  String? _bloodGroup;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _c = {
      'name': TextEditingController(text: u.name),
      'phone': TextEditingController(text: u.phone ?? ''),
      'enrollmentNo': TextEditingController(text: u.enrollmentNo ?? ''),
      'course': TextEditingController(text: u.course ?? ''),
      'year': TextEditingController(text: u.year ?? ''),
      'dateOfBirth': TextEditingController(text: u.dateOfBirth ?? ''),
      'address': TextEditingController(text: u.address ?? ''),
      'guardianName': TextEditingController(text: u.guardianName ?? ''),
      'guardianPhone': TextEditingController(text: u.guardianPhone ?? ''),
      'guardianRelation': TextEditingController(text: u.guardianRelation ?? ''),
      'notes': TextEditingController(text: u.notes ?? ''),
    };
    _gender = u.gender;
    _bloodGroup = u.bloodGroup;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _val(String key) {
    final t = _c[key]!.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DataService.instance.updateUser(widget.user.uid, {
        'name': _c['name']!.text.trim(),
        'phone': _val('phone'),
        'gender': _gender,
        'enrollmentNo': _val('enrollmentNo'),
        'course': _val('course'),
        'year': _val('year'),
        'dateOfBirth': _val('dateOfBirth'),
        'bloodGroup': _bloodGroup,
        'address': _val('address'),
        'guardianName': _val('guardianName'),
        'guardianPhone': _val('guardianPhone'),
        'guardianRelation': _val('guardianRelation'),
        'notes': _val('notes'),
      });
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Details saved')));
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final canEdit = session.can(Perm.usersEdit);

    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              widget.user.initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${widget.user.email} · ${widget.user.displayRole}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  _ErrorBox(_error!),
                  const SizedBox(height: 16),
                ],

                // ---------------- Room ----------------
                _RoomSection(user: widget.user),
                const SizedBox(height: 22),

                _SectionLabel('Personal'),
                _Field(_c['name']!, 'Full name', enabled: canEdit && !_busy,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Name is required'
                        : null),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        _c['phone']!,
                        'Phone',
                        enabled: canEdit && !_busy,
                        keyboard: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: DropdownButtonFormField<String>(
                          initialValue: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            helperText: 'Used for hostel eligibility',
                          ),
                          items: const ['Male', 'Female', 'Other']
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                          onChanged: canEdit && !_busy
                              ? (v) => setState(() => _gender = v)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        _c['dateOfBirth']!,
                        'Date of birth',
                        hint: 'DD/MM/YYYY',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: DropdownButtonFormField<String>(
                          initialValue: _bloodGroup,
                          decoration: const InputDecoration(
                            labelText: 'Blood group',
                          ),
                          items:
                              const [
                                    'A+',
                                    'A-',
                                    'B+',
                                    'B-',
                                    'O+',
                                    'O-',
                                    'AB+',
                                    'AB-',
                                  ]
                                  .map(
                                    (g) => DropdownMenuItem(
                                      value: g,
                                      child: Text(g),
                                    ),
                                  )
                                  .toList(),
                          onChanged: canEdit && !_busy
                              ? (v) => setState(() => _bloodGroup = v)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _SectionLabel('Academic'),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        _c['enrollmentNo']!,
                        'Enrollment / Employee no.',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        _c['course']!,
                        'Course',
                        hint: 'B.Tech CSE',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        _c['year']!,
                        'Year',
                        hint: '2nd',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _SectionLabel('Guardian & emergency contact'),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _Field(
                        _c['guardianName']!,
                        'Guardian name',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        _c['guardianRelation']!,
                        'Relation',
                        hint: 'Father',
                        enabled: canEdit && !_busy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _Field(
                        _c['guardianPhone']!,
                        'Guardian phone',
                        enabled: canEdit && !_busy,
                        keyboard: TextInputType.phone,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _SectionLabel('Other'),
                _Field(
                  _c['address']!,
                  'Permanent address',
                  enabled: canEdit && !_busy,
                  lines: 2,
                ),
                _Field(
                  _c['notes']!,
                  'Internal notes',
                  hint: 'Only staff can see this',
                  enabled: canEdit && !_busy,
                  lines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(canEdit ? 'Cancel' : 'Close'),
        ),
        if (canEdit)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save details'),
          ),
      ],
    );
  }
}

/// Live room status for this user, with allot / move / vacate actions.
class _RoomSection extends StatelessWidget {
  final AppUser user;
  const _RoomSection({required this.user});

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final canAllot = session.can(Perm.allotmentManage);

    // Watch the user document so the card updates the moment a room is
    // allotted, without closing and reopening this dialog.
    return StreamBuilder<AppUser?>(
      stream: AuthService.instance.watchProfile(user.uid),
      initialData: user,
      builder: (context, snap) {
        final u = snap.data ?? user;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: u.isAllotted ? AppColors.successSoft : AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: u.isAllotted ? AppColors.success : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                u.isAllotted
                    ? Icons.meeting_room_rounded
                    : Icons.no_meeting_room_rounded,
                color: u.isAllotted ? AppColors.success : AppColors.textMuted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.isAllotted ? u.roomLabel! : 'No room allotted',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      u.isAllotted
                          ? 'Allotted room'
                          : 'This person hasn\'t been given a bed yet.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (canAllot && !u.isSuperAdmin) ...[
                if (u.isAllotted) ...[
                  TextButton(
                    onPressed: () => _openAllot(context, u, move: true),
                    child: const Text('Change'),
                  ),
                  TextButton(
                    onPressed: () => _vacate(context, u),
                    child: const Text(
                      'Vacate',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => _openAllot(context, u, move: false),
                    child: const Text('Allot room'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAllot(
    BuildContext context,
    AppUser u, {
    required bool move,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => AllotRoomDialog(student: u, isMove: move),
    );
  }

  Future<void> _vacate(BuildContext context, AppUser u) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Vacate ${u.roomLabel}?'),
        content: Text(
          '${u.name} will be removed from the room and the bed freed up.',
        ),
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
        SnackBar(content: Text(_describe(e))),
      );
    }
  }

  static String _describe(Object e) =>
      e is AllotmentFailure ? e.message : AuthService.describeError(e);
}

// ------------------------------ small pieces ------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool enabled;
  final int lines;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field(
    this.controller,
    this.label, {
    this.hint,
    this.enabled = true,
    this.lines = 1,
    this.keyboard,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: lines,
      keyboardType: keyboard,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      message,
      style: const TextStyle(color: AppColors.danger, fontSize: 13),
    ),
  );
}
