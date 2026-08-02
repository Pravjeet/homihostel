import 'package:flutter/material.dart';

import '../../core/identity.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../services/allotment_service.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import 'allot_room_view.dart';

/// The full record for one person: everything that wasn't asked for at
/// account creation, plus their room.
///
/// Account creation deliberately stays minimal — name, email, password, role.
/// Everything else is optional detail you fill in when you have it, which is
/// what this screen is for.
///
/// Rendered as a drill-down *inside* the dashboard shell (same pattern as
/// [HostelDetailView]) rather than a dialog, so the sidebar stays visible and
/// there is room for the full form.
class UserDetailView extends StatefulWidget {
  final String uid;
  final AppUser initial;
  final VoidCallback onBack;

  const UserDetailView({
    super.key,
    required this.uid,
    required this.initial,
    required this.onBack,
  });

  @override
  State<UserDetailView> createState() => _UserDetailViewState();
}

class _UserDetailViewState extends State<UserDetailView> {
  /// Non-null while the allot/move picker is showing in place of the details.
  bool? _allotIsMove;

  @override
  Widget build(BuildContext context) {
    // Watch the document so the room card and header stay live while the form
    // is open — allotting a room updates this page without a reload.
    return StreamBuilder<AppUser?>(
      stream: AuthService.instance.watchProfile(widget.uid),
      initialData: widget.initial,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This user no longer exists.'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: widget.onBack,
                  child: const Text('Back to users'),
                ),
              ],
            ),
          );
        }

        if (_allotIsMove != null) {
          return AllotRoomView(
            student: user,
            isMove: _allotIsMove!,
            onBack: () => setState(() => _allotIsMove = null),
            onDone: () => setState(() => _allotIsMove = null),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(user: user, onBack: widget.onBack),
            const SizedBox(height: 18),
            _RoomSection(
              user: user,
              onAllot: (move) => setState(() => _allotIsMove = move),
            ),
            const SizedBox(height: 18),
            // Keyed on uid so switching users rebuilds the controllers with
            // the new person's values instead of keeping the old text.
            _DetailForm(
              key: ValueKey(widget.uid),
              user: user,
              onDone: widget.onBack,
            ),
          ],
        );
      },
    );
  }
}

// -------------------------------- header --------------------------------

class _Header extends StatelessWidget {
  final AppUser user;
  final VoidCallback onBack;
  const _Header({required this.user, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to users',
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              user.initials,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${Identity.display(user.email)} · ${user.displayRole}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!user.isActive)
            const StatusPill(
              'DISABLED',
              AppColors.danger,
              AppColors.dangerSoft,
            ),
        ],
      ),
    );
  }
}

// --------------------------------- form ---------------------------------

class _DetailForm extends StatefulWidget {
  final AppUser user;
  final VoidCallback onDone;
  const _DetailForm({super.key, required this.user, required this.onDone});

  @override
  State<_DetailForm> createState() => _DetailFormState();
}

class _DetailFormState extends State<_DetailForm> {
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
      messenger.showSnackBar(const SnackBar(content: Text('Details saved')));
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = Session.of(context).can(Perm.usersEdit);
    final on = canEdit && !_busy;

    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(canEdit ? 'Edit details' : 'Details'),
            const SizedBox(height: 18),

            if (_error != null) ...[
              _ErrorBox(_error!),
              const SizedBox(height: 16),
            ],

            const _SectionLabel('Personal'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _Field(
                    _c['name']!,
                    'Full name',
                    enabled: on,
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Name is required'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    _c['phone']!,
                    'Phone',
                    enabled: on,
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
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: on ? (v) => setState(() => _gender = v) : null,
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
                    enabled: on,
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
                          const ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-']
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                      onChanged: on
                          ? (v) => setState(() => _bloodGroup = v)
                          : null,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),

            const SizedBox(height: 8),
            const _SectionLabel('Academic'),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    _c['enrollmentNo']!,
                    'Enrollment / Employee no.',
                    enabled: on,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    _c['course']!,
                    'Course',
                    hint: 'B.Tech CSE',
                    enabled: on,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(_c['year']!, 'Year', hint: '2nd', enabled: on),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const _SectionLabel('Guardian & emergency contact'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _Field(
                    _c['guardianName']!,
                    'Guardian name',
                    enabled: on,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    _c['guardianRelation']!,
                    'Relation',
                    hint: 'Father',
                    enabled: on,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _Field(
                    _c['guardianPhone']!,
                    'Guardian phone',
                    enabled: on,
                    keyboard: TextInputType.phone,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            const _SectionLabel('Other'),
            _Field(
              _c['address']!,
              'Permanent address',
              enabled: on,
              lines: 2,
            ),
            _Field(
              _c['notes']!,
              'Internal notes',
              hint: 'Only staff can see this',
              enabled: on,
              lines: 2,
            ),

            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : widget.onDone,
                  child: Text(canEdit ? 'Cancel' : 'Back'),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                    ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------ room section ------------------------------

/// Live room status for this user, with allot / move / vacate actions.
class _RoomSection extends StatelessWidget {
  final AppUser user;

  /// `true` = relocate an already-allotted student, `false` = first allotment.
  final ValueChanged<bool> onAllot;

  const _RoomSection({required this.user, required this.onAllot});

  @override
  Widget build(BuildContext context) {
    final canAllot = Session.of(context).can(Perm.allotmentManage);
    final u = user;

    return AppCard(
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
                    fontSize: 15,
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
                onPressed: () => onAllot(true),
                child: const Text('Change room'),
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
                onPressed: () => onAllot(false),
                child: const Text('Allot room'),
              ),
          ],
        ],
      ),
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
      await AllotmentService.instance.vacate(collegeId: u.collegeId, student: u);
      messenger.showSnackBar(const SnackBar(content: Text('Room vacated')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_describe(e))));
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
