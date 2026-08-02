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
                    style: const TextStyle(
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
                        style: const TextStyle(
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
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      helperText:
                          'Email and role are managed by your administrator.',
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
