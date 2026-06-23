import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';

class PermissionsView extends StatefulWidget {
  final String collegeId;

  const PermissionsView({super.key, required this.collegeId});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _isLoading = false;
  bool _isSaving = false;

  Map<String, Map<String, bool>> _rolePermissions = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _isLoading = true);

    try {
      final permissions = await _authService.getPermissions(widget.collegeId);
      setState(() {
        _rolePermissions = permissions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load permissions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _updatePermission(String role, String permission, bool value) {
    setState(() {
      _rolePermissions[role]![permission] = value;
    });
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    try {
      await _authService.updatePermissions(
        collegeId: widget.collegeId,
        permissions: _rolePermissions,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissions saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save permissions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String _formatPermissionName(String permission) {
    return permission
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  IconData _getPermissionIcon(String permission) {
    switch (permission) {
      case 'manage_users':
        return Icons.people;
      case 'manage_rooms':
        return Icons.meeting_room;
      case 'view_reports':
        return Icons.assessment;
      case 'manage_complaints':
        return Icons.report_problem;
      case 'manage_fees':
        return Icons.payment;
      case 'manage_attendance':
        return Icons.check_circle;
      case 'manage_visitors':
        return Icons.circle;
      case 'send_notifications':
        return Icons.notifications;
      default:
        return Icons.settings;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'Chief Warden':
        return Colors.purple;
      case 'Warden':
        return Colors.blue;
      case 'Student':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'Chief Warden':
        return Icons.admin_panel_settings;
      case 'Warden':
        return Icons.shield;
      case 'Student':
        return Icons.person;
      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.security_rounded, color: Colors.purple, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Permissions',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Manage role-based access permissions',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _savePermissions,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Permissions Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _rolePermissions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.security,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No permissions configured',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: _rolePermissions.entries.map((roleEntry) {
                    final role = roleEntry.key;
                    final permissions = roleEntry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: _getRoleColor(role).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _getRoleIcon(role),
                                    color: _getRoleColor(role),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      role,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${permissions.values.where((v) => v).length} of ${permissions.length} permissions enabled',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 12),
                            ...permissions.entries.map((permEntry) {
                              final permission = permEntry.key;
                              final isEnabled = permEntry.value;

                              return InkWell(
                                onTap: () => _updatePermission(
                                  role,
                                  permission,
                                  !isEnabled,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getPermissionIcon(permission),
                                        size: 20,
                                        color: isEnabled
                                            ? Colors.blue
                                            : Colors.grey.shade400,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _formatPermissionName(permission),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isEnabled
                                                ? Colors.black87
                                                : Colors.grey.shade500,
                                          ),
                                        ),
                                      ),
                                      Switch(
                                        value: isEnabled,
                                        onChanged: (value) {
                                          _updatePermission(
                                            role,
                                            permission,
                                            value,
                                          );
                                        },
                                        activeColor: Colors.blue,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}
