import 'package:flutter/widgets.dart';

import '../models/app_role.dart';
import '../models/app_user.dart';

/// Everything the UI needs to know about "who is looking at this screen".
///
/// Exposed through an [InheritedWidget] so any widget can call
/// `Session.of(context).can(Perm.usersEdit)` without prop-drilling and
/// without pulling in a state-management package.
@immutable
class Session {
  final AppUser user;
  final AppRole? role;
  final String collegeName;

  const Session({required this.user, this.role, required this.collegeName});

  /// SuperAdmin short-circuits every check — they own the workspace.
  bool can(String permission) =>
      user.isSuperAdmin || (role?.permissions.contains(permission) ?? false);

  bool canAny(List<String> permissions) => permissions.any(can);

  /// A user with no role assigned yet gets a friendly holding screen instead
  /// of an empty dashboard.
  bool get hasNoAccess =>
      !user.isSuperAdmin && (role == null || role!.permissions.isEmpty);

  static Session of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found above this widget.');
    return scope!.session;
  }
}

class SessionScope extends InheritedWidget {
  final Session session;

  const SessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      oldWidget.session.user.uid != session.user.uid ||
      oldWidget.session.role?.permissions != session.role?.permissions ||
      oldWidget.session.user.name != session.user.name;
}

/// Convenience for reading permissions inline in build methods.
extension SessionContext on BuildContext {
  Session get session => Session.of(this);
  bool can(String permission) => Session.of(this).can(permission);
}
