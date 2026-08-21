import 'package:flutter/material.dart';

import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/app_role.dart';
import '../../models/app_user.dart';
import '../../models/hostel.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';
import '../../services/hostel_service.dart';

/// A filterable directory of residents — trade, year, semester, hostel,
/// home state, batch.
///
/// Reads straight off [AppUser], not off `Enrollment` (see
/// enrollment_service.dart) — this page's job is a snapshot of the whole
/// roster right now, not a session-scoped view, so it stays independent of
/// whether backfill has been run and never gates on a current session being
/// set. `year` in particular is whatever free text a sheet or a warden typed
/// ("2nd", "II", ...), not a normalised ordinal, so the filter options are
/// exactly the distinct strings actually in use rather than a clean
/// 1st/2nd/3rd/4th list. `batch` is cleaner — see
/// `batchFromRegistrationNo` — but is filtered the same way for consistency.
///
/// Deliberately read-only: no drill-down, no editing. Users & Roles already
/// owns editing a student; Room Allotment already owns moving them; Academic
/// Records owns promotion and the year-by-session breakdown. This page
/// answers one question — "who, filtered by these six things" — and stops
/// there.
///
/// Paginated the same way as Users / Room Allotment: rendering every match
/// at once is what makes a large roster crawl.
class StudentOverviewPage extends StatefulWidget {
  const StudentOverviewPage({super.key});

  @override
  State<StudentOverviewPage> createState() => _StudentOverviewPageState();
}

class _StudentOverviewPageState extends State<StudentOverviewPage> {
  String? _trade;
  String? _year;
  int? _sem;
  String? _hostel;
  String? _state;
  String? _batch;

  static const _pageSize = 50;
  int _page = 0;

  /// Hostel full name -> short code, so a filter chip reads "BH-5" rather
  /// than the full "CV Raman House".
  Map<String, String> _codes = const {};

  String _hostelLabel(String? name) {
    if (name == null || name.trim().isEmpty) return 'Unallotted';
    return _codes[name] ?? name;
  }

  /// `state` is only as good as the address it was parsed from, so a blank is
  /// common and gets its own bucket — the same 'Not set' wording the fines
  /// dashboard uses — rather than being silently dropped from the roster.
  static const _noState = 'Not set';

  static String _stateLabel(String? s) =>
      (s == null || s.trim().isEmpty) ? _noState : s;

  bool _keep(AppUser u) =>
      (_trade == null || u.trade == _trade) &&
      (_year == null || u.year == _year) &&
      (_sem == null || u.sem == _sem) &&
      (_hostel == null || _hostelLabel(u.hostelName) == _hostel) &&
      (_state == null || _stateLabel(u.state) == _state) &&
      (_batch == null || u.batch == _batch);

  bool get _anyFilter =>
      _trade != null ||
      _year != null ||
      _sem != null ||
      _hostel != null ||
      _state != null ||
      _batch != null;

  void _clearAll() => setState(() {
    _trade = null;
    _year = null;
    _sem = null;
    _hostel = null;
    _state = null;
    _batch = null;
    _page = 0;
  });

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final collegeId = session.user.collegeId;

    if (!session.can(Perm.usersView)) {
      return AppCard(
        padding: const EdgeInsets.symmetric(vertical: 54),
        child: Center(
          child: Text(
            'You don\'t have permission to view the student directory.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return StreamBuilder<List<Hostel>>(
      stream: HostelService.instance.watchHostels(collegeId),
      builder: (context, hostelSnap) {
        final hostels = hostelSnap.data ?? const <Hostel>[];
        _codes = {
          for (final h in hostels)
            if (h.code.trim().isNotEmpty) h.name: h.code,
        };

        return StreamBuilder<List<AppRole>>(
          stream: DataService.instance.watchRoles(collegeId),
          builder: (context, roleSnap) {
            // Staff who manage hostels aren't residents — excluded from the
            // directory the same way Room Allotment excludes the Super
            // Admin, so trade/year/sem columns aren't full of staff blanks.
            final staffRoleIds = (roleSnap.data ?? const <AppRole>[])
                .where((r) => Perm.managesHostels(r.permissions))
                .map((r) => r.id)
                .toSet();

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

                final roster = userSnap.data!
                    .where((u) => !u.isSuperAdmin)
                    .where((u) => !staffRoleIds.contains(u.roleId))
                    .toList();

                final shown = roster.where(_keep).toList()
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

                // Every option comes from the UNFILTERED roster — building
                // them from `shown` would make picking a filter erase the
                // very options that could get you back out of it.
                final tradeOptions = ({
                  for (final u in roster)
                    if (u.trade != null) u.trade!,
                }.toList()..sort());
                final yearOptions = ({
                  for (final u in roster)
                    if (u.year != null) u.year!,
                }.toList()..sort());
                final semOptions = ({
                  for (final u in roster)
                    if (u.sem != null) u.sem!,
                }.toList()..sort());
                final hostelOptions = ({
                  for (final u in roster) _hostelLabel(u.hostelName),
                  // BH-10 belongs after BH-9, not between BH-1 and BH-2.
                }.toList()..sort(Hostel.compareLabels));
                // 'Not set' is not a place, so it sorts to the end instead of
                // landing between Nagaland and Odisha.
                final stateOptions =
                    ({for (final u in roster) _stateLabel(u.state)}.toList()
                      ..sort((a, b) {
                        if (a == _noState) return 1;
                        if (b == _noState) return -1;
                        return a.compareTo(b);
                      }));
                // Descending: the most recent intake is what a warden is
                // usually looking for, not the oldest one still on the books.
                final batchOptions = ({
                  for (final u in roster)
                    if (u.batch != null) u.batch!,
                }.toList()..sort((a, b) => b.compareTo(a)));

                final pageCount = shown.isEmpty
                    ? 1
                    : (shown.length / _pageSize).ceil();
                final page = _page.clamp(0, pageCount - 1);
                final pageStart = page * _pageSize;
                final pageItems = shown
                    .skip(pageStart)
                    .take(_pageSize)
                    .toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      total: roster.length,
                      shown: shown.length,
                      anyFilter: _anyFilter,
                      onClear: _clearAll,
                    ),
                    const SizedBox(height: 14),
                    _Filters(
                      tradeOptions: tradeOptions,
                      yearOptions: yearOptions,
                      sems: semOptions,
                      hostelOptions: hostelOptions,
                      stateOptions: stateOptions,
                      batchOptions: batchOptions,
                      trade: _trade,
                      year: _year,
                      sem: _sem,
                      hostel: _hostel,
                      state: _state,
                      batch: _batch,
                      tradeLabelFor: session.settings.tradeLabelFor,
                      onTrade: (v) => setState(() {
                        _trade = v;
                        _page = 0;
                      }),
                      onYear: (v) => setState(() {
                        _year = v;
                        _page = 0;
                      }),
                      onSem: (v) => setState(() {
                        _sem = v;
                        _page = 0;
                      }),
                      onHostel: (v) => setState(() {
                        _hostel = v;
                        _page = 0;
                      }),
                      onState: (v) => setState(() {
                        _state = v;
                        _page = 0;
                      }),
                      onBatch: (v) => setState(() {
                        _batch = v;
                        _page = 0;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _StudentList(students: pageItems),
                    if (pageCount > 1) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: page > 0
                                ? () => setState(() => _page = page - 1)
                                : null,
                            child: const Text('Previous'),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Page ${page + 1} of $pageCount  '
                              '(${pageStart + 1}–'
                              '${pageStart + pageItems.length} of '
                              '${shown.length})',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: page < pageCount - 1
                                ? () => setState(() => _page = page + 1)
                                : null,
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// ------------------------------- header -------------------------------

class _Header extends StatelessWidget {
  final int total;
  final int shown;
  final bool anyFilter;
  final VoidCallback onClear;

  const _Header({
    required this.total,
    required this.shown,
    required this.anyFilter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Student Overview'),
        const SizedBox(height: 4),
        Text(
          'Filter the resident roster by trade, year, semester, hostel '
          'and home state.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              anyFilter ? '$shown of $total students' : '$total students',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (anyFilter) ...[
              const SizedBox(width: 14),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

// ------------------------------- filters -------------------------------

class _Filters extends StatelessWidget {
  final List<String> tradeOptions;
  final List<String> yearOptions;
  final List<int> sems;
  final List<String> hostelOptions;
  final List<String> stateOptions;
  final List<String> batchOptions;
  final String? trade;
  final String? year;
  final int? sem;
  final String? hostel;
  final String? state;
  final String? batch;
  final String Function(String) tradeLabelFor;
  final ValueChanged<String?> onTrade;
  final ValueChanged<String?> onYear;
  final ValueChanged<int?> onSem;
  final ValueChanged<String?> onHostel;
  final ValueChanged<String?> onState;
  final ValueChanged<String?> onBatch;

  const _Filters({
    required this.tradeOptions,
    required this.yearOptions,
    required this.sems,
    required this.hostelOptions,
    required this.stateOptions,
    required this.batchOptions,
    required this.trade,
    required this.year,
    required this.sem,
    required this.hostel,
    required this.state,
    required this.batch,
    required this.tradeLabelFor,
    required this.onTrade,
    required this.onYear,
    required this.onSem,
    required this.onHostel,
    required this.onState,
    required this.onBatch,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Drop<String>(
          label: 'Trade',
          value: trade,
          options: tradeOptions,
          labelFor: tradeLabelFor,
          onChanged: onTrade,
          width: 220,
        ),
        _Drop<String>(
          label: 'Year',
          value: year,
          options: yearOptions,
          onChanged: onYear,
          width: 140,
        ),
        _Drop<int>(
          label: 'Semester',
          value: sem,
          options: sems,
          labelFor: (s) => 'Sem $s',
          onChanged: onSem,
          width: 130,
        ),
        _Drop<String>(
          label: 'Hostel',
          value: hostel,
          options: hostelOptions,
          onChanged: onHostel,
          width: 170,
        ),
        _Drop<String>(
          label: 'Home state',
          value: state,
          options: stateOptions,
          onChanged: onState,
          width: 200,
        ),
        _Drop<String>(
          label: 'Batch',
          value: batch,
          options: batchOptions,
          onChanged: onBatch,
          width: 140,
        ),
      ],
    ),
  );
}

class _Drop<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> options;
  final String Function(T)? labelFor;
  final ValueChanged<T?> onChanged;
  final double width;

  const _Drop({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelFor,
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DropdownButtonFormField<T>(
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      hint: const Text('All'),
      items: [
        DropdownMenuItem<T>(value: null, child: const Text('All')),
        ...options.map(
          (o) => DropdownMenuItem(
            value: o,
            child: Text(
              labelFor == null ? '$o' : labelFor!(o),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    ),
  );
}

// -------------------------------- list ---------------------------------

class _StudentList extends StatelessWidget {
  final List<AppUser> students;
  const _StudentList({required this.students});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Text(
            'No students match these filters.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < students.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _StudentRow(student: students[i]),
          ],
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final AppUser student;
  const _StudentRow({required this.student});

  @override
  Widget build(BuildContext context) {
    final u = student;
    final hostelLabel = u.hostelName == null
        ? null
        : (u.roomNumber == null
              ? u.hostelName
              : '${u.hostelName} · ${u.roomNumber}');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              u.initials,
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
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
                  u.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (u.enrollmentNo != null) u.enrollmentNo!,
                    if (u.course != null) u.course!,
                  ].join('  ·  '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              u.trade ?? '—',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Builder(
              builder: (context) {
                final parts = [
                  if (u.year != null) u.year!,
                  if (u.sem != null) 'Sem ${u.sem}',
                ];
                return Text(
                  parts.isEmpty ? '—' : parts.join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: hostelLabel == null
                ? StatusPill(
                    'UNALLOTTED',
                    AppColors.warning,
                    AppColors.warningSoft,
                  )
                : Text(
                    hostelLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
          ),
        ],
      ),
    );
  }
}
