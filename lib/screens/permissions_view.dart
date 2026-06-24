import 'package:flutter/material.dart';
import 'permissions.dart'; // Import the file containing RolePermissions and PermissionsService

class PermissionsView extends StatefulWidget {
  final String collegeId;

  const PermissionsView({super.key, required this.collegeId});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView> {
  final PermissionsService _permissionsService = PermissionsService();
  List<RolePermissions> _rolesPermissions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPermissions();
  }

  Future<void> _fetchPermissions() async {
    setState(() => _isLoading = true);
    final permissions = await _permissionsService.getAllRolePermissions(
      widget.collegeId,
    );

    // If no permissions exist yet (first time login), initialize them
    if (permissions.isEmpty) {
      await _permissionsService.initializeDefaultPermissions(widget.collegeId);
      final newPermissions = await _permissionsService.getAllRolePermissions(
        widget.collegeId,
      );
      setState(() {
        _rolesPermissions = newPermissions;
        _isLoading = false;
      });
    } else {
      setState(() {
        _rolesPermissions = permissions;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePermission(
    RolePermissions role,
    String permissionType,
    bool newValue,
  ) async {
    RolePermissions updatedRole;

    switch (permissionType) {
      case 'read':
        updatedRole = role.copyWith(canRead: newValue);
        break;
      case 'get':
        updatedRole = role.copyWith(canGet: newValue);
        break;
      case 'list':
        updatedRole = role.copyWith(canList: newValue);
        break;
      case 'write':
        updatedRole = role.copyWith(canWrite: newValue);
        break;
      case 'create':
        updatedRole = role.copyWith(canCreate: newValue);
        break;
      case 'update':
        updatedRole = role.copyWith(canUpdate: newValue);
        break;
      case 'delete':
        updatedRole = role.copyWith(canDelete: newValue);
        break;
      default:
        return;
    }

    // Optimistic UI update
    setState(() {
      int index = _rolesPermissions.indexWhere(
        (r) => r.roleName == role.roleName,
      );
      if (index != -1) {
        _rolesPermissions[index] = updatedRole;
      }
    });

    // Save to Firestore
    try {
      await _permissionsService.updateRolePermission(
        collegeId: widget.collegeId,
        updatedPermission: updatedRole,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissions updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Revert UI if update fails
      _fetchPermissions();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rolesPermissions.isEmpty) {
      return const Center(child: Text("No roles found."));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Role Permissions Configuration',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Toggle specific database access capabilities for each system role.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView.builder(
            itemCount: _rolesPermissions.length,
            itemBuilder: (context, index) {
              final role = _rolesPermissions[index];
              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.roleName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                      const Divider(height: 30),

                      // Read Permissions Group
                      const Text(
                        'Read Access',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 20,
                        runSpacing: 10,
                        children: [
                          _buildToggle(
                            'Global Read (Get + List)',
                            role.canRead,
                            (val) => _togglePermission(role, 'read', val),
                          ),
                          _buildToggle(
                            'Single Doc (Get)',
                            role.canGet,
                            (val) => _togglePermission(role, 'get', val),
                          ),
                          _buildToggle(
                            'Query/List',
                            role.canList,
                            (val) => _togglePermission(role, 'list', val),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Write Permissions Group
                      const Text(
                        'Write Access',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 20,
                        runSpacing: 10,
                        children: [
                          _buildToggle(
                            'Global Write (C/U/D)',
                            role.canWrite,
                            (val) => _togglePermission(role, 'write', val),
                          ),
                          _buildToggle(
                            'Create',
                            role.canCreate,
                            (val) => _togglePermission(role, 'create', val),
                          ),
                          _buildToggle(
                            'Update',
                            role.canUpdate,
                            (val) => _togglePermission(role, 'update', val),
                          ),
                          _buildToggle(
                            'Delete',
                            role.canDelete,
                            (val) => _togglePermission(role, 'delete', val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blueAccent,
          ),
        ],
      ),
    );
  }
}
