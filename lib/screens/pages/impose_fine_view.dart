import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

/// Largest order photo accepted, in bytes. Base64 adds ~33% on top of this,
/// and a Firestore document tops out around 1 MB, so this leaves headroom
/// for the fine and order fields alongside it.
const int _maxOrderImageBytes = 700 * 1024;

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Form for staff to impose a fine on a resident.
///
/// The student is chosen from a live search rather than typed, so the fine
/// always lands on a real uid — a fine attached to a mistyped name would be
/// invisible to the student it was meant for.
///
/// Every fine here comes with the office order it was issued under — the two
/// are created together in one write ([FineService.imposeWithOfficeOrder]),
/// so this form collects both: the fine's amount/category/reason, and the
/// order's number/date/photo. There is no path to impose a fine without an
/// order behind it.
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
  final _search = TextEditingController();

  final _orderNo = TextEditingController();
  final _orderTitle = TextEditingController();
  final _orderDescription = TextEditingController();
  DateTime _orderDate = DateTime.now();
  Uint8List? _orderImageBytes;
  String? _orderImageMimeType;
  String? _orderImageName;

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
    _search.dispose();
    _orderNo.dispose();
    _orderTitle.dispose();
    _orderDescription.dispose();
    super.dispose();
  }

  static const _mimeByExt = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<void> _pickOrderImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    if (file.bytes!.lengthInBytes > _maxOrderImageBytes) {
      setState(() {
        _error = 'That photo is too large '
            '(${(file.bytes!.lengthInBytes / 1024).round()} KB). Please '
            'keep it under ${_maxOrderImageBytes ~/ 1024} KB — a phone camera '
            'shot usually compresses well below that.';
      });
      return;
    }

    final ext = file.extension?.toLowerCase() ?? '';
    setState(() {
      _error = null;
      _orderImageBytes = file.bytes;
      _orderImageMimeType = _mimeByExt[ext] ?? 'image/jpeg';
      _orderImageName = file.name;
    });
  }

  Future<void> _pickOrderDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() => _orderDate = picked);
  }

  Future<void> _submit() async {
    if (_student == null) {
      setState(() => _error = 'Choose the student this fine is against.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_orderImageBytes == null) {
      setState(() => _error = 'Add a photo of the office order before submitting');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final session = Session.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FineService.instance.imposeWithOfficeOrder(
        collegeId: session.user.collegeId,
        student: _student!,
        imposedBy: session.user,
        amount: num.parse(_amount.text.trim()),
        category: _category ?? kFineCategories.first,
        reason: _reason.text,
        orderNo: _orderNo.text,
        orderTitle: _orderTitle.text,
        orderImageBytes: _orderImageBytes!,
        orderImageMimeType: _orderImageMimeType!,
        orderDescription: _orderDescription.text,
        orderDate: _orderDate,
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
                ],
              ),
            ),
            const SizedBox(height: 18),

            // --------------------- office order ---------------------
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Office order',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Every fine is issued under an order — fill in what was '
                    'printed and attach a photo of it.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _orderNo,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Office order number',
                            hintText: 'SLIET/HM/2026/17',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Order number is required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: _busy ? null : _pickOrderDate,
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Order date',
                              suffixIcon: Icon(
                                Icons.calendar_today_rounded,
                                size: 17,
                              ),
                            ),
                            child: Text(
                              '${_orderDate.day} '
                              '${_monthNames[_orderDate.month - 1]} '
                              '${_orderDate.year}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _orderTitle,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      hintText: 'e.g., Disciplinary action for curfew violation',
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Subject is required (at least 3 characters)'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Photo of the order',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_orderImageBytes != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _orderImageBytes!,
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _orderImageName ?? 'Photo selected',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${(_orderImageBytes!.lengthInBytes / 1024).round()} KB',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _pickOrderImage,
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 16,
                                ),
                                label: const Text('Choose a different photo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickOrderImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose a photo (JPG/PNG, under 700 KB)'),
                    ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _orderDescription,
                    enabled: !_busy,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Summary (optional)',
                      alignLabelWithHint: true,
                      hintText: 'A line or two on what the order says, so '
                          'people can find it without opening the photo.',
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
