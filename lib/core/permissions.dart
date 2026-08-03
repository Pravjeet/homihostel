/// Central permission catalogue.
///
/// A permission is a plain string `"<module>.<action>"`. A Role owns a
/// `Set<String>` of them. Everything in the UI (sidebar entries, buttons,
/// pages) asks `session.can(Perm.xxx)` instead of comparing role *names*.
/// This is what lets you invent a brand new role like "Hostel Manager"
/// without touching a single `if (role == ...)` in the codebase.
library;

class Perm {
  // Users
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersEdit = 'users.edit';
  static const usersDelete = 'users.delete';

  // Roles & permissions
  static const rolesView = 'roles.view';
  static const rolesManage = 'roles.manage';

  // Hostels / rooms
  static const hostelsView = 'hostels.view';
  static const hostelsManage = 'hostels.manage';
  static const allotmentManage = 'allotment.manage';

  // Mess
  static const messView = 'mess.view';
  static const messManage = 'mess.manage';

  // Requests (leave / maintenance / other)
  static const requestsViewOwn = 'requests.viewOwn';
  static const requestsViewAll = 'requests.viewAll';
  static const requestsApprove = 'requests.approve';
  static const requestsCreate = 'requests.create';

  // Fines
  static const finesViewOwn = 'fines.viewOwn';
  static const finesViewAll = 'fines.viewAll';
  static const finesManage = 'fines.manage';

  // Office orders
  static const officeOrdersView = 'officeOrders.view';
  static const officeOrdersManage = 'officeOrders.manage';

  // Notices
  static const noticesView = 'notices.view';
  static const noticesManage = 'notices.manage';

  // Student self-service
  static const selfRoom = 'self.room';

  // Settings
  static const settingsManage = 'settings.manage';

  /// Grouped for the permission-picker UI.
  static const Map<String, List<PermissionDef>> catalogue = {
    'User Management': [
      PermissionDef(usersView, 'View users', 'See the user directory'),
      PermissionDef(usersCreate, 'Create users', 'Add new accounts'),
      PermissionDef(usersEdit, 'Edit users', 'Change details and roles'),
      PermissionDef(usersDelete, 'Delete users', 'Remove accounts'),
    ],
    'Roles & Permissions': [
      PermissionDef(rolesView, 'View roles', 'See roles and their access'),
      PermissionDef(rolesManage, 'Manage roles', 'Create, edit, delete roles'),
    ],
    'Hostel & Rooms': [
      PermissionDef(hostelsView, 'View hostels', 'See blocks and rooms'),
      PermissionDef(hostelsManage, 'Manage hostels', 'Add/edit blocks, rooms'),
      PermissionDef(allotmentManage, 'Room allotment', 'Assign students'),
    ],
    'Mess': [
      PermissionDef(messView, 'View mess', 'Menu, wallet, transactions'),
      PermissionDef(messManage, 'Manage mess', 'Edit menu and wallets'),
    ],
    'Requests': [
      PermissionDef(requestsCreate, 'Raise requests', 'Submit own requests'),
      PermissionDef(requestsViewOwn, 'View own requests', 'Track own requests'),
      PermissionDef(requestsViewAll, 'View all requests', 'See everyone\'s'),
      PermissionDef(requestsApprove, 'Approve requests', 'Approve or reject'),
    ],
    'Fines': [
      PermissionDef(finesViewOwn, 'View own fines', 'See fines raised on you'),
      PermissionDef(finesViewAll, 'View all fines', 'Fines dashboard and roster'),
      PermissionDef(finesManage, 'Manage fines', 'Impose, waive and mark paid'),
    ],
    'Office Orders': [
      PermissionDef(officeOrdersView, 'View office orders', 'Read issued orders'),
      PermissionDef(officeOrdersManage, 'Manage office orders', 'Publish orders'),
    ],
    'Notices': [
      PermissionDef(noticesView, 'View notices', 'Read announcements'),
      PermissionDef(noticesManage, 'Manage notices', 'Publish announcements'),
    ],
    'Student Self-Service': [
      PermissionDef(selfRoom, 'My room', 'View own room and roommates'),
    ],
    'System': [
      PermissionDef(settingsManage, 'System settings', 'Institution settings'),
    ],
  };

  static List<String> get all =>
      catalogue.values.expand((l) => l).map((p) => p.key).toList();
}

class PermissionDef {
  final String key;
  final String label;
  final String description;
  const PermissionDef(this.key, this.label, this.description);
}

/// Starter role templates offered to the SuperAdmin. These are *suggestions*
/// written into Firestore once; the admin can freely edit them afterwards.
const Map<String, List<String>> kRoleTemplates = {
  'Chief Warden': [
    Perm.usersView,
    Perm.usersCreate,
    Perm.usersEdit,
    Perm.hostelsView,
    Perm.hostelsManage,
    Perm.allotmentManage,
    Perm.messView,
    Perm.messManage,
    Perm.requestsViewAll,
    Perm.requestsApprove,
    Perm.finesViewAll,
    Perm.finesManage,
    Perm.officeOrdersView,
    Perm.officeOrdersManage,
    Perm.noticesView,
    Perm.noticesManage,
  ],
  'Warden': [
    Perm.usersView,
    Perm.hostelsView,
    Perm.allotmentManage,
    Perm.messView,
    Perm.requestsViewAll,
    Perm.requestsApprove,
    Perm.finesViewAll,
    Perm.finesManage,
    Perm.officeOrdersView,
    Perm.noticesView,
  ],
  'Hostel Manager': [
    Perm.usersView,
    Perm.hostelsView,
    Perm.hostelsManage,
    Perm.messView,
    Perm.messManage,
    Perm.requestsViewAll,
    Perm.finesViewAll,
    Perm.finesManage,
    Perm.officeOrdersView,
    Perm.officeOrdersManage,
    Perm.noticesView,
  ],
  'Student': [
    Perm.selfRoom,
    Perm.messView,
    Perm.noticesView,
    Perm.requestsCreate,
    Perm.requestsViewOwn,
    Perm.finesViewOwn,
    Perm.officeOrdersView,
  ],
};
