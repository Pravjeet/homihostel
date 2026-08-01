import 'package:flutter/material.dart';
import 'permissions.dart';

class PermissionsView extends StatefulWidget {
  final String collegeId;

  const PermissionsView({super.key, required this.collegeId});

  @override
  State<PermissionsView> createState() => PermissionsViewState();
}

class PermissionsViewState extends State<PermissionsView> {
  final PermissionsService _permissionsService = PermissionsService();

  List<RolePermissions> _roles = [];
  bool _isLoading = false;
  bool _isSaving = false;

  final Map<String, List<Map<String, String>>> _permissionCategories =
      PermissionsService.getPermissionCategories();

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> refreshPermissions() async {
    await _loadRoles();
  }

  Future<void> _loadRoles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final fetchedRoles = await _permissionsService.getAllRolePermissions(
        widget.collegeId,
      );

      if (!mounted) return;

      // Filter out SuperAdmin role
      final filteredRoles = fetchedRoles
          .where((role) => role.roleName != 'SuperAdmin')
          .toList();

      setState(() {
        _roles = filteredRoles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load roles: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateRolePermissions(RolePermissions updatedRole) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await _permissionsService.updateRolePermission(
        collegeId: widget.collegeId,
        updatedPermission: updatedRole,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;

        final index = _roles.indexWhere(
          (r) => r.roleName == updatedRole.roleName,
        );

        if (index != -1) {
          _roles[index] = updatedRole;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Permissions for ${updatedRole.roleName} updated successfully.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update permissions: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPermissionToggle(
    String permissionKey,
    String permissionLabel,
    bool value,
    RolePermissions role,
  ) {
    return SwitchListTile(
      dense: true,
      title: Text(
        permissionLabel,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: value ? Colors.blue.shade900 : Colors.grey.shade700,
        ),
      ),
      value: value,
      onChanged: _isSaving
          ? null
          : (newValue) {
              setState(() {
                final updatedRole = role.copyWith(
                  canRead: permissionKey == 'read' ? newValue : role.canRead,
                  canGet: permissionKey == 'get' ? newValue : role.canGet,
                  canList: permissionKey == 'list' ? newValue : role.canList,
                  canWrite: permissionKey == 'write' ? newValue : role.canWrite,
                  canCreate: permissionKey == 'create'
                      ? newValue
                      : role.canCreate,
                  canUpdate: permissionKey == 'update'
                      ? newValue
                      : role.canUpdate,
                  canDelete: permissionKey == 'delete'
                      ? newValue
                      : role.canDelete,
                );

                final index = _roles.indexWhere(
                  (r) => r.roleName == role.roleName,
                );

                if (index != -1) {
                  _roles[index] = updatedRole;
                }
              });
            },
    );
  }

  bool _getPermissionValue(RolePermissions role, String key) {
    switch (key) {
      case 'read':
        return role.canRead;
      case 'get':
        return role.canGet;
      case 'list':
        return role.canList;
      case 'write':
        return role.canWrite;
      case 'create':
        return role.canCreate;
      case 'update':
        return role.canUpdate;
      case 'delete':
        return role.canDelete;
      default:
        return false;
    }
  }

  int _getPermissionCount(RolePermissions role) {
    return [
      role.canRead,
      role.canGet,
      role.canList,
      role.canWrite,
      role.canCreate,
      role.canUpdate,
      role.canDelete,
    ].where((e) => e).length;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Permissions Management',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Configure role access permissions',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _isLoading ? null : _loadRoles,
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: Colors.blue.shade700,
                      ),
                      tooltip: 'Refresh Permissions',
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Info card when no roles exist
          if (!_isLoading && _roles.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.shade100),
              ),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create roles in the Role Management tab first, then configure their permissions here.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _roles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No roles created yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create roles in the Role Management tab first',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _roles.length,
                    itemBuilder: (context, index) {
                      final role = _roles[index];
                      final count = _getPermissionCount(role);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings,
                                color: count > 0
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade500,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                role.roleName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(left: 36.0, top: 4),
                            child: Text(
                              '$count / 7 permissions enabled',
                              style: TextStyle(
                                color: count > 0
                                    ? Colors.blue.shade600
                                    : Colors.grey.shade500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  ..._permissionCategories.entries.map((
                                    category,
                                  ) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                              top: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  category.key ==
                                                          'Read Operations'
                                                      ? Icons.visibility
                                                      : Icons.edit,
                                                  size: 18,
                                                  color: Colors.grey.shade700,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  category.key,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.grey.shade700,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                                maxCrossAxisExtent: 350,
                                                mainAxisExtent: 60,
                                              ),
                                          itemCount: category.value.length,
                                          itemBuilder: (context, permIndex) {
                                            final permission =
                                                category.value[permIndex];

                                            final key = permission['key']!;
                                            final label = permission['label']!;

                                            return _buildPermissionToggle(
                                              key,
                                              label,
                                              _getPermissionValue(role, key),
                                              role,
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }),

                                  const SizedBox(height: 20),
                                  Divider(color: Colors.grey.shade200),
                                  const SizedBox(height: 16),

                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () {
                                              final updatedRole = _roles
                                                  .firstWhere(
                                                    (r) =>
                                                        r.roleName ==
                                                        role.roleName,
                                                  );

                                              _updateRolePermissions(
                                                updatedRole,
                                              );
                                            },
                                      icon: _isSaving
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.save),
                                      label: Text(
                                        _isSaving
                                            ? 'Saving...'
                                            : 'Save Changes',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
