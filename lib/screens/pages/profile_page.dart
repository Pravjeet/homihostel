import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/identity.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/data_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController? _name;
  TextEditingController? _phone;
  bool _busy = false;

  @override
  void dispose() {
    _name?.dispose();
    _phone?.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DataService.instance.updateUser(uid, {
        'name': _name!.text.trim(),
        'phone': _phone!.text.trim().isEmpty ? null : _phone!.text.trim(),
      });
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_EmailChangeRequest>(
      context: context,
      builder: (_) => const _ChangeEmailDialog(),
    );
    if (result == null) return;

    try {
      await AuthService.instance.changeOwnEmail(
        currentPassword: result.password,
        newEmail: result.newEmail,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Confirmation link sent to ${result.newEmail}. Click it to '
            'finish the change — keep signing in with your current email '
            'until then.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.describeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Session.of(context);
    final user = session.user;
    _name ??= TextEditingController(text: user.name);
    _phone ??= TextEditingController(text: user.phone ?? '');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    user.initials,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Identity.display(user.email),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusPill(
                        user.displayRole.toUpperCase(),
                        AppColors.primary,
                        AppColors.primarySoft,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('Edit your details'),
                  const SizedBox(height: 18),
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
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: Identity.display(user.email),
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      helperText: Identity.isSynthetic(user.email)
                          ? 'Accounts that sign in with a registration '
                                'number don\'t have an email to change.'
                          : null,
                      suffixIcon: Identity.isSynthetic(user.email)
                          ? null
                          : TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _changeEmail(context),
                              child: const Text('Change'),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _busy ? null : () => _save(user.uid),
                        child: const Text('Save changes'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await AuthService.instance.sendPasswordReset(
                                  Identity.display(user.email),
                                );
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Password reset email sent'),
                                  ),
                                );
                              },
                        child: const Text('Reset password'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailChangeRequest {
  final String newEmail;
  final String password;
  const _EmailChangeRequest(this.newEmail, this.password);
}

/// Collects the new address plus the current password — email changes are
/// security-sensitive, so Firebase requires a recent sign-in, and asking here
/// is friendlier than surfacing a raw "requires-recent-login" error later.
class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog();

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change your email'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'We\'ll send a confirmation link to the new address. Your '
                'sign-in email only changes once you click it.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'New email'),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Enter your new email address';
                  if (!s.contains('@') || !s.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  helperText: 'Needed to confirm this is really you.',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Your current password is required'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _EmailChangeRequest(_email.text.trim(), _password.text),
            );
          },
          child: const Text('Send confirmation link'),
        ),
      ],
    );
  }
}
