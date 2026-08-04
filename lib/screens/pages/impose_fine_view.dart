import 'package:flutter/material.dart';

import '../../core/identity.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/college_settings.dart';
import '../../models/fine.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import '../../services/fine_service.dart';

/// Form for staff to impose a fine on a resident.
///
/// The student is chosen from a live search rather than typed, so the fine
/// always lands on a real uid — a fine attached to a mistyped name would be
/// invisible to the student it was meant for.
class ImposeFineView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onDone;

  /// Pre-selected student, when arriving from someone's fine history.
  final AppUser? student;

  const ImposeFineView({
    super.key,
    required this.onBack,
    required this.onDone,
    this.student,
  });

  @override
  State<ImposeFineView> createState() => _ImposeFineViewState();
}

class _ImposeFineViewState extends State<ImposeFineView> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _officeOrderNo = TextEditingController();
  final _search = TextEditingController();

  AppUser? _student;

  /// Null until the first build reads the workspace's configured categories —
  /// Session isn't available from initState.
  String? _category;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
  }

  /// Pre-fills the amount when the chosen category has a configured default,
  /// but never overwrites something already typed.
  void _applyDefault(List<FineCategory> configured, String category) {
    if (_amount.text.trim().isNotEmpty) return;
    for (final c in configured) {
      if (c.name == category && c.defaultAmount != null) {
        _amount.text = '${c.defaultAmount}';
        return;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _officeOrderNo.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_student == null) {
      setState(() => _error = 'Choose the student this fine is against.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final session = Session.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FineService.instance.impose(
        collegeId: session.user.collegeId,
        student: _student!,
        imposedBy: session.user,
        amount: num.parse(_amount.text.trim()),
        category: _category ?? kFineCategories.first,
        reason: _reason.text,
        officeOrderNo: _officeOrderNo.text,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Fine imposed on ${_student!.name}')),
      );
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;

    // Categories come from System Settings, falling back to the built-in list
    // when nobody has configured any.
    final categories = session.settings.categoryNames;
    _category ??= categories.first;
    if (!categories.contains(_category)) _category = categories.first;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _busy ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back to fines',
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Impose a fine',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ------------------------- who -------------------------
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_student != null)
                    _SelectedStudent(
                      student: _student!,
                      onClear: _busy
                          ? null
                          : () => setState(() => _student = null),
                    )
                  else ...[
                    TextField(
                      controller: _search,
                      enabled: !_busy,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search by name, registration number or room',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StudentResults(
                      collegeId: collegeId,
                      query: _search.text,
                      onPick: (u) => setState(() {
                        _student = u;
                        _error = null;
                      }),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ------------------------- what -------------------------
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _amount,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                          ),
                          validator: (v) {
                            final n = num.tryParse(v?.trim() ?? '');
                            if (n == null) return 'Enter an amount';
                            if (n <= 0) return 'Must be more than zero';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Reason category',
                          ),
                          items: categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                  _category = v ?? categories.first;
                                  _applyDefault(
                                    session.settings.fineCategories,
                                    _category!,
                                  );
                                }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _reason,
                    enabled: !_busy,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                      alignLabelWithHint: true,
                      hintText: 'What happened, and when. The student sees '
                          'this on their fines list.',
                    ),
                    validator: (v) => (v == null || v.trim().length < 5)
                        ? 'Say what the fine is for (at least 5 characters)'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _officeOrderNo,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Office order number (optional)',
                      hintText: 'SLIET/HM/2026/17',
                      helperText: 'If this fine was issued under an order',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : widget.onBack,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
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
                            : const Text('Impose fine'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedStudent extends StatelessWidget {
  final AppUser student;
  final VoidCallback? onClear;

  const _SelectedStudent({required this.student, this.onClear});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primary,
          child: Text(
            student.initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitleFor(student),
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (onClear != null)
          TextButton(onPressed: onClear, child: const Text('Change')),
      ],
    ),
  );
}

String _subtitleFor(AppUser u) => [
  Identity.display(u.email),
  if (u.roomLabel != null) u.roomLabel!,
  if (u.trade != null) u.trade!,
  if (u.sem != null) 'Sem ${u.sem}',
].join(' · ');

/// Live student picker. Shows nothing until at least two characters are typed
/// — a college has hundreds of residents and an unfiltered list is useless.
class _StudentResults extends StatelessWidget {
  final String collegeId;
  final String query;
  final ValueChanged<AppUser> onPick;

  const _StudentResults({
    required this.collegeId,
    required this.query,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'Type at least two characters to find a student.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return StreamBuilder<List<AppUser>>(
      stream: DataService.instance.watchUsers(collegeId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(AuthService.describeError(snap.error!));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final matches = snap.data!
            .where((u) => !u.isSuperAdmin)
            .where(
              (u) =>
                  u.name.toLowerCase().contains(q) ||
                  (u.enrollmentNo ?? '').toLowerCase().contains(q) ||
                  (u.roomNumber ?? '').toLowerCase().contains(q),
            )
            .take(8)
            .toList();

        if (matches.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Nobody matches that.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < matches.length; i++) ...[
                InkWell(
                  onTap: () => onPick(matches[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primarySoft,
                          child: Text(
                            matches[i].initials,
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
                                matches[i].name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _subtitleFor(matches[i]),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (i != matches.length - 1)
                  Divider(height: 1, color: AppColors.border),
              ],
            ],
          ),
        );
      },
    );
  }
}
