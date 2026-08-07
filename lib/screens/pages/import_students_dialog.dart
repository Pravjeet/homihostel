import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../models/app_role.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/auth_service.dart';
import '../../services/csv_import.dart';

/// Bulk import: paste a sheet, check the preview, run it.
///
/// Three explicit steps, and nothing is written until you've seen exactly what
/// will happen. Imports get run twice by accident constantly, so the preview
/// isn't a nicety — it's the safety mechanism.
class ImportStudentsDialog extends StatefulWidget {
  /// Passed in rather than read from the context.
  ///
  /// `showDialog` pushes a route onto the *root* Navigator, so this widget's
  /// context is a sibling of the dashboard's — not a descendant. `SessionScope`
  /// lives below that Navigator (see `auth_gate.dart`), which means
  /// `Session.of(context)` inside a dialog finds nothing and throws. The caller
  /// reads the session from the page's own context and hands us the one value
  /// we actually need.
  final String collegeId;

  final List<AppUser> existingUsers;
  final List<AppRole> roles;
  final List<Hostel> hostels;

  /// The college's trade list, passed in for the same reason as [collegeId].
  final List<String> knownTrades;

  const ImportStudentsDialog({
    super.key,
    required this.collegeId,
    required this.existingUsers,
    required this.roles,
    this.hostels = const [],
    this.knownTrades = kTrades,
  });

  @override
  State<ImportStudentsDialog> createState() => _ImportStudentsDialogState();
}

class _ImportStudentsDialogState extends State<ImportStudentsDialog> {
  final _paste = TextEditingController();

  int _step = 0; // 0 paste · 1 preview · 2 running/done
  ImportPlan? _plan;
  String? _parseError;
  String _defaultRole = '';

  bool _running = false;
  bool _stopRequested = false;
  int _done = 0;
  int _total = 0;
  String _currentLabel = '';
  ImportOutcome? _outcome;

  /// A failure that killed the whole run, as opposed to a single bad row.
  /// Without this the dialog would sit on "0 of N" forever with no
  /// explanation, because the exception escaped _run() silently.
  String? _fatalError;

  /// Mirrors "is the paste box non-empty", so the Preview button can enable
  /// itself. Without a listener the button's onPressed is only evaluated on
  /// rebuild, and typing alone never triggers one.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _paste.addListener(() {
      final has = _paste.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    final assignable = widget.roles.where((r) => !r.isSystem).toList();
    final student = assignable.where(
      (r) => r.name.toLowerCase() == 'student',
    );
    _defaultRole = student.isNotEmpty
        ? student.first.name
        : (assignable.isEmpty ? '' : assignable.first.name);
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _analyse() {
    final table = parseDelimited(_paste.text);
    if (table.isEmpty) {
      setState(
        () => _parseError =
            'Nothing to import. Paste at least a header row and one data row.',
      );
      return;
    }
    setState(() {
      _parseError = null;
      _plan = analyseImport(
        table: table,
        existingUsers: widget.existingUsers,
        roles: widget.roles,
        hostels: widget.hostels,
        defaultRoleName: _defaultRole,
        knownTrades: widget.knownTrades,
      );
      _step = 1;
    });
  }

  Future<void> _run() async {
    final plan = _plan!;
    final collegeId = widget.collegeId;

    // Move to the progress step FIRST, and put every subsequent statement
    // inside the try. Anything thrown before this point would land in a
    // Future that `onPressed` discards — an unhandled async error that shows
    // up only as an engine stack trace in the browser console, with the
    // dialog sitting there looking fine. This is how the Session lookup that
    // used to live here stayed invisible.
    setState(() {
      _step = 2;
      _running = true;
      _stopRequested = false;
      _fatalError = null;
      _done = 0;
      _total = plan.rows.where((r) => r.isValid).length;
    });

    try {
      final outcome = await runImport(
        plan: plan,
        collegeId: collegeId,
        onProgress: (done, total, label) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
              _currentLabel = label;
            });
          }
        },
        isCancelled: () => _stopRequested,
      );
      if (mounted) setState(() => _outcome = outcome);
    } catch (e, st) {
      debugPrint('Import failed: $e\n$st');
      if (mounted) {
        setState(() => _fatalError = AuthService.describeError(e));
      }
    } finally {
      // Must run whatever happened, or the dialog stays stuck on "Working…".
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        switch (_step) {
          0 => 'Import people from a spreadsheet',
          1 => 'Check before importing',
          _ => _running ? 'Importing…' : 'Import finished',
        },
      ),
      content: SizedBox(
        width: 720,
        height: 540,
        child: switch (_step) {
          0 => _PasteStep(
            controller: _paste,
            error: _parseError,
            roles: widget.roles.where((r) => !r.isSystem).toList(),
            defaultRole: _defaultRole,
            onDefaultRoleChanged: (v) => setState(() => _defaultRole = v),
          ),
          1 => _PreviewStep(plan: _plan!),
          _ => _RunStep(
            running: _running,
            stopRequested: _stopRequested,
            done: _done,
            total: _total,
            label: _currentLabel,
            outcome: _outcome,
            fatalError: _fatalError,
          ),
        },
      ),
      actions: switch (_step) {
        0 => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _hasText ? _analyse : null,
            child: const Text('Preview'),
          ),
        ],
        1 => [
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: (_plan?.canRun ?? false) ? _run : null,
            child: Text(
              _plan == null
                  ? 'Import'
                  : (_plan!.creates + _plan!.updates == 0
                        ? 'Nothing to import'
                        : 'Import ${_plan!.creates + _plan!.updates}'),
            ),
          ),
        ],
        _ => [
          if (_running)
            TextButton(
              onPressed: _stopRequested
                  ? null
                  : () => setState(() => _stopRequested = true),
              child: Text(_stopRequested ? 'Stopping…' : 'Stop'),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
        ],
      },
    );
  }
}

// ------------------------------- step 1 -------------------------------

class _PasteStep extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final List<AppRole> roles;
  final String defaultRole;
  final ValueChanged<String> onDefaultRoleChanged;

  const _PasteStep({
    required this.controller,
    required this.error,
    required this.roles,
    required this.defaultRole,
    required this.onDefaultRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Open your CSV in Excel or Notepad, select everything, copy, and '
          'paste it below. Each row needs a name and either a registration '
          'number or an email — every other column can be left blank.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: templateHeaderRow()),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Header row copied — paste into Excel'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copy template headers'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: templateWithExample()),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Template + example copied')),
                  );
                }
              },
              icon: const Icon(Icons.description_outlined, size: 17),
              label: const Text('With example row'),
            ),
            const Spacer(),
            if (roles.isNotEmpty)
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  initialValue: roles.any((r) => r.name == defaultRole)
                      ? defaultRole
                      : roles.first.name,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Role if column is blank',
                    isDense: true,
                  ),
                  items: roles
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.name,
                          child: Text(r.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => onDefaultRoleChanged(v ?? ''),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (error != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              error!,
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText:
                  'name,email,role,enrollmentNo,...\n'
                  'Aarav Sharma,aarav@sliet.ac.in,Student,21CS128,...',
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tabs or commas both work, so a direct copy out of Excel is fine.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ------------------------------- step 2 -------------------------------

class _PreviewStep extends StatelessWidget {
  final ImportPlan plan;
  const _PreviewStep({required this.plan});

  @override
  Widget build(BuildContext context) {
    if (plan.missingColumns.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: AppColors.danger,
            ),
            const SizedBox(height: 14),
            Text(
              'Missing required column${plan.missingColumns.length == 1 ? '' : 's'}: '
              '${plan.missingColumns.join(', ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Go back and make sure your first pasted line is the header row.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.creates + plan.updates == 0) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Nothing can be imported — all ${plan.skips} row(s) were '
              'skipped, so the Import button is disabled. The reason for '
              'each row is shown in red below. The usual cause is a role '
              'name in the sheet that does not exist yet.',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            _Tally('Will create', plan.creates, AppColors.success),
            const SizedBox(width: 26),
            _Tally('Will update', plan.updates, AppColors.primary),
            const SizedBox(width: 26),
            _Tally('Skipped', plan.skips, AppColors.danger),
            const SizedBox(width: 26),
            _Tally('Rooms allotted', plan.allotments, AppColors.info),
          ],
        ),
        if (plan.unknownColumns.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Ignored column${plan.unknownColumns.length == 1 ? '' : 's'}: '
            '${plan.unknownColumns.join(', ')}',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: plan.rows.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) => _RowTile(row: plan.rows[i]),
          ),
        ),
        if (plan.creates > 40) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${plan.creates} new accounts is a lot for the browser to create '
              '— Firebase throttles this, so expect it to be slow and for some '
              'rows to fail. Any that fail are listed at the end and you can '
              're-run safely.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Tally(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );
}

class _RowTile extends StatelessWidget {
  final ImportRow row;
  const _RowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (row.action) {
      RowAction.create => ('NEW', AppColors.success, AppColors.successSoft),
      RowAction.update => ('UPDATE', AppColors.primary, AppColors.primarySoft),
      RowAction.skip => ('SKIP', AppColors.danger, AppColors.dangerSoft),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${row.lineNumber}',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          StatusPill(label, color, bg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name.isEmpty ? '(no name)' : row.name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (row.loginLabel.isNotEmpty) row.loginLabel,
                    if (row.role != null) row.role!.name,
                    if (row.values['enrollmentNo'] != null)
                      row.values['enrollmentNo']!,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                if (row.problems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      row.problems.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (row.warnings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      row.warnings.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (row.wantsAllotment)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '→ ${row.hostel!.name}, room ${row.roomNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
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
}

// ------------------------------- step 3 -------------------------------

class _RunStep extends StatelessWidget {
  final bool running;
  final bool stopRequested;
  final int done;
  final int total;
  final String label;
  final ImportOutcome? outcome;
  final String? fatalError;

  const _RunStep({
    required this.running,
    required this.stopRequested,
    required this.done,
    required this.total,
    required this.label,
    required this.outcome,
    this.fatalError,
  });

  @override
  Widget build(BuildContext context) {
    if (fatalError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: AppColors.danger,
            ),
            const SizedBox(height: 14),
            const Text(
              'The import stopped',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                fatalError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              done == 0
                  ? 'Nothing was written.'
                  : '$done row(s) were processed before it stopped. '
                        'Re-running is safe — existing people are updated, '
                        'not duplicated.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    if (running) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$done of $total',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              minHeight: 8,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 22),
          Text(
            stopRequested
                ? 'Stopping after the student currently being imported…'
                : 'Please leave this window open until it finishes.',
            style: TextStyle(
              color: stopRequested ? AppColors.warning : AppColors.textMuted,
              fontSize: 12.5,
              fontWeight: stopRequested ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      );
    }

    final o = outcome;
    if (o == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Tally('Created', o.created, AppColors.success),
            const SizedBox(width: 26),
            _Tally('Updated', o.updated, AppColors.primary),
            const SizedBox(width: 26),
            _Tally('Rooms allotted', o.allotted, AppColors.info),
            const SizedBox(width: 26),
            _Tally('Failed', o.failures.length, AppColors.danger),
          ],
        ),
        const SizedBox(height: 18),
        if (o.stoppedEarly)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Stopped early — ${o.remaining} row(s) were never attempted. '
              'Re-run the same file to pick up where this left off; rows '
              'already imported are matched by email and updated, not '
              'duplicated.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.warning,
                height: 1.45,
              ),
            ),
          ),
        if (o.created > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'New students sign in with their registration number, and their '
              'starting password IS their registration number. Tell them to '
              'change it from My Profile after the first login.',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF075985),
                height: 1.45,
              ),
            ),
          ),
        if (o.allotmentIssues.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Accounts were created, but these rooms could not be allotted:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 90,
            child: ListView(
              children: o.allotmentIssues
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (o.failures.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'These rows failed — fix them and paste just those rows again:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: o.failures
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}
