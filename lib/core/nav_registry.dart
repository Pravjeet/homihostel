import 'package:flutter/material.dart';

import '../screens/pages/allotment_page.dart';
import '../screens/pages/coming_soon_page.dart';
import '../screens/pages/hostels_page.dart';
import '../screens/pages/my_room_page.dart';
import '../screens/pages/overview_page.dart';
import '../screens/pages/profile_page.dart';
import '../screens/pages/roles_page.dart';
import '../screens/pages/users_page.dart';
import 'permissions.dart';
import 'session.dart';

/// One entry in the sidebar.
class NavItem {
  final String id;
  final String label;
  final IconData icon;

  /// Shown only if the session holds at least one of these. Empty = always.
  final List<String> requires;

  final WidgetBuilder builder;

  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.requires = const [],
    required this.builder,
  });
}

class NavSection {
  final String? title;
  final List<NavItem> items;
  const NavSection({this.title, required this.items});
}

/// THE single source of truth for navigation.
///
/// Every role — SuperAdmin, Warden, Student — renders from this same list.
/// The only difference between what two users see is which entries survive
/// the permission filter. Add a feature once, and it appears for exactly the
/// roles that were granted it.
const List<NavSection> _allSections = [
  NavSection(
    items: [
      NavItem(
        id: 'overview',
        label: 'Dashboard',
        icon: Icons.dashboard_rounded,
        builder: _overview,
      ),
    ],
  ),
  NavSection(
    title: 'People',
    items: [
      NavItem(
        id: 'users',
        label: 'User Management',
        icon: Icons.group_rounded,
        requires: [Perm.usersView],
        builder: _users,
      ),
      NavItem(
        id: 'roles',
        label: 'Roles & Permissions',
        icon: Icons.verified_user_rounded,
        requires: [Perm.rolesView],
        builder: _roles,
      ),
    ],
  ),
  NavSection(
    title: 'Hostel',
    items: [
      NavItem(
        id: 'hostels',
        label: 'Hostels & Rooms',
        icon: Icons.apartment_rounded,
        requires: [Perm.hostelsView],
        builder: _hostels,
      ),
      NavItem(
        id: 'allotment',
        label: 'Room Allotment',
        icon: Icons.bed_rounded,
        requires: [Perm.allotmentManage],
        builder: _allotment,
      ),
      NavItem(
        id: 'my-room',
        label: 'My Room',
        icon: Icons.meeting_room_rounded,
        requires: [Perm.selfRoom],
        builder: _myRoom,
      ),
    ],
  ),
  NavSection(
    title: 'Operations',
    items: [
      NavItem(
        id: 'mess',
        label: 'Mess',
        icon: Icons.restaurant_rounded,
        requires: [Perm.messView],
        builder: _mess,
      ),
      NavItem(
        id: 'requests',
        label: 'Requests',
        icon: Icons.assignment_turned_in_rounded,
        requires: [
          Perm.requestsViewAll,
          Perm.requestsViewOwn,
          Perm.requestsCreate,
        ],
        builder: _requests,
      ),
      NavItem(
        id: 'notices',
        label: 'Notices',
        icon: Icons.campaign_rounded,
        requires: [Perm.noticesView],
        builder: _notices,
      ),
      NavItem(
        id: 'finance',
        label: 'Finance',
        icon: Icons.payments_rounded,
        requires: [Perm.financeView],
        builder: _finance,
      ),
    ],
  ),
  NavSection(
    title: 'Account',
    items: [
      NavItem(
        id: 'profile',
        label: 'My Profile',
        icon: Icons.person_rounded,
        builder: _profile,
      ),
      NavItem(
        id: 'settings',
        label: 'System Settings',
        icon: Icons.settings_rounded,
        requires: [Perm.settingsManage],
        builder: _settings,
      ),
      NavItem(
        id: 'audit',
        label: 'Audit Logs',
        icon: Icons.receipt_long_rounded,
        requires: [Perm.auditView],
        builder: _audit,
      ),
    ],
  ),
];

/// Filters the master list down to what this session may see.
List<NavSection> navigationFor(Session session) {
  final result = <NavSection>[];
  for (final section in _allSections) {
    final visible = section.items
        .where((i) => i.requires.isEmpty || session.canAny(i.requires))
        .toList();
    if (visible.isNotEmpty) {
      result.add(NavSection(title: section.title, items: visible));
    }
  }
  return result;
}

// Page builders. These are top-level functions rather than `Page.new` tear-offs
// because a WidgetBuilder takes a BuildContext, and because only top-level
// function references are const — which `_allSections` requires.
Widget _overview(BuildContext c) => const OverviewPage();
Widget _users(BuildContext c) => const UsersPage();
Widget _roles(BuildContext c) => const RolesPage();
Widget _myRoom(BuildContext c) => const MyRoomPage();
Widget _profile(BuildContext c) => const ProfilePage();

// Placeholder builders for modules you haven't built yet. Replacing one is a
// one-line change here — the sidebar, routing and gating already work.
Widget _hostels(BuildContext c) => const HostelsPage();
Widget _allotment(BuildContext c) => const AllotmentPage();
Widget _mess(BuildContext c) => const ComingSoonPage(
  title: 'Mess',
  icon: Icons.restaurant_rounded,
  blurb: 'Weekly menu, mess wallet and transactions.',
);
Widget _requests(BuildContext c) => const ComingSoonPage(
  title: 'Requests',
  icon: Icons.assignment_turned_in_rounded,
  blurb: 'Leave, maintenance and other requests with approvals.',
);
Widget _notices(BuildContext c) => const ComingSoonPage(
  title: 'Notices',
  icon: Icons.campaign_rounded,
  blurb: 'Announcements broadcast to students and staff.',
);
Widget _finance(BuildContext c) => const ComingSoonPage(
  title: 'Finance',
  icon: Icons.payments_rounded,
  blurb: 'Payments, dues tracking and revenue reports.',
);
Widget _settings(BuildContext c) => const ComingSoonPage(
  title: 'System Settings',
  icon: Icons.settings_rounded,
  blurb: 'Institution profile, branding and preferences.',
);
Widget _audit(BuildContext c) => const ComingSoonPage(
  title: 'Audit Logs',
  icon: Icons.receipt_long_rounded,
  blurb: 'A record of who changed what, and when.',
);
