import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added for custom fields
import 'firebase_auth_service.dart';
import 'permissions.dart';

class RolesView extends StatefulWidget {
  final String collegeId;

  const RolesView({super.key, required this.collegeId});

  @override
  State<RolesView> createState() => RolesViewState();
}

class RolesViewState extends State<RolesView> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  final PermissionsService _permissionsService = PermissionsService();
  final TextEditingController _newRoleController = TextEditingController();

  bool _isLoading = false;
  bool _isCreatingRole = false;
  bool _isCleaningUp = false;
  bool _isDeletingRole = false;
  List<Map<String, dynamic>> _allUsers = [];
  List<RolePermissions> _allRoles = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _newRoleController.dispose();
    super.dispose();
  }

  Future<void> refreshUsers() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final fetchedUsers = await _authService.getUsersByCollegeId(
        widget.collegeId,
      );

      final fetchedRoles = await _permissionsService.getAllRolePermissions(
        widget.collegeId,
      );

      // Filter out SuperAdmin from the roles list
      final filteredRoles = fetchedRoles
          .where((role) => role.roleName != 'SuperAdmin')
          .toList();

      if (!mounted) return;

      setState(() {
        _allUsers = fetchedUsers;
        _allRoles = filteredRoles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createNewRole() async {
    final roleName = _newRoleController.text.trim();

    if (roleName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a role name.'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if role already exists
    final bool roleExists = _allRoles.any(
      (role) => role.roleName.toLowerCase() == roleName.toLowerCase(),
    );

    if (roleExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This role already exists.'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if trying to create SuperAdmin
    if (roleName.toLowerCase() == 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot create SuperAdmin role.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isCreatingRole = true;
    });

    try {
      // Create role with default permissions (all false)
      Map<String, bool> defaultPermissions = {
        'read': false,
        'get': false,
        'list': false,
        'write': false,
        'create': false,
        'update': false,
        'delete': false,
      };

      await _permissionsService.createRoleWithPermissions(
        collegeId: widget.collegeId,
        roleName: roleName,
        permissions: defaultPermissions,
      );

      // Reload roles
      final fetchedRoles = await _permissionsService.getAllRolePermissions(
        widget.collegeId,
      );

      // Filter out SuperAdmin
      final filteredRoles = fetchedRoles
          .where((role) => role.roleName != 'SuperAdmin')
          .toList();

      if (!mounted) return;

      setState(() {
        _allRoles = filteredRoles;
        _newRoleController.clear();
        _isCreatingRole = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Role "$roleName" created successfully with 0 permissions.',
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isCreatingRole = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create role: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- NEW METHOD: Add Custom Field Dialog ---
  void _showAddFieldDialog(String roleName) {
    final TextEditingController fieldController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Field to $roleName'),
        content: TextField(
          controller: fieldController,
          decoration: const InputDecoration(
            labelText: 'Field Name (e.g., Department, Grade)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (fieldController.text.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection('colleges')
                      .doc(widget.collegeId)
                      .collection('roles')
                      .doc(roleName)
                      .set({
                        'customFields': FieldValue.arrayUnion([
                          fieldController.text.trim(),
                        ]),
                      }, SetOptions(merge: true));

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {}); // Refresh UI to trigger FutureBuilder
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Custom field added.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to add field: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Add Field'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRole(String roleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('Delete Role'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete the role "$roleName"?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Any users assigned to this role will become unassigned.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever, size: 20),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeletingRole = true);

      try {
        await _permissionsService.deleteRolePermissions(
          collegeId: widget.collegeId,
          roleName: roleName,
        );

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Role "$roleName" deleted successfully.'),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete role: $e'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isDeletingRole = false);
      }
    }
  }

  Future<void> _cleanupRoles() async {
    if (_allRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No roles to clean up.'),
          backgroundColor: Colors.blue.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange.shade700,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Text('Clean Up All Roles'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to delete ${_allRoles.length} role(s):',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _allRoles
                    .map(
                      (role) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              role.roleName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '⚠️ Any users assigned to these roles will become unassigned.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '✅ SuperAdmin role will be preserved.',
              style: TextStyle(
                color: Colors.green.shade700,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_forever, size: 20),
            label: const Text('Delete All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isCleaningUp = true);

      try {
        await _permissionsService.cleanupAllRoles(widget.collegeId);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'All roles cleaned up successfully. SuperAdmin role preserved.',
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cleanup failed: $e'),
              backgroundColor: Colors.red.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isCleaningUp = false);
      }
    }
  }

  Future<void> _changeUserRole(
    String uid,
    String userName,
    String? newRole,
  ) async {
    final previousUsers = List<Map<String, dynamic>>.from(_allUsers);

    setState(() {
      final userIndex = _allUsers.indexWhere((u) => u['uid'] == uid);
      if (userIndex != -1) {
        _allUsers[userIndex]['role'] = newRole;
      }
    });

    try {
      await _authService.updateUserRole(uid: uid, newRole: newRole);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$userName assigned to ${newRole ?? 'Unassigned'}'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _allUsers = previousUsers;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update role: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedUsers = _allUsers
        .where((u) => u['role'] != 'SuperAdmin')
        .toList();

    // Build role names list for dropdown (exclude SuperAdmin)
    List<String?> roleNames = [null];
    // Unassigned option
    roleNames.addAll(_allRoles.map((role) => role.roleName).toList());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- HEADER SECTION ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Role Management',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Create new roles and assign them to users.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  // Cleanup Button (only show if roles exist)
                  if (_allRoles.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: _isCleaningUp
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red.shade700,
                                ),
                              )
                            : Icon(
                                Icons.cleaning_services_rounded,
                                color: Colors.red.shade700,
                              ),
                        onPressed:
                            (_isLoading || _isCleaningUp || _isDeletingRole)
                            ? null
                            : _cleanupRoles,
                        tooltip: 'Clean Up All Roles',
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: Colors.blue.shade700,
                      ),
                      onPressed: _isLoading ? null : refreshUsers,
                      tooltip: 'Refresh Data',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.sync_rounded,
                        color: Colors.green.shade700,
                      ),
                      onPressed: _isLoading ? null : _loadData,
                      tooltip: 'Sync Roles from Firebase',
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // --- CREATE ROLE SECTION ---
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Create New Role',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (_allRoles.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_allRoles.length} roles exist',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newRoleController,
                          enabled: !_isCreatingRole,
                          decoration: InputDecoration(
                            hintText: 'e.g., Assistant Warden, Maintenance',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: Icon(
                              Icons.badge_outlined,
                              color: Colors.grey.shade500,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Colors.blue.shade400,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _createNewRole(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _isCreatingRole ? null : _createNewRole,
                        icon: _isCreatingRole
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(
                          _isCreatingRole ? 'Creating...' : 'Add Role',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tip: New roles are created with 0 permissions. Configure permissions in the Permissions tab.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // --- AVAILABLE ROLES LIST (UPDATED WITH CUSTOM FIELDS) ---
          if (_allRoles.isNotEmpty) ...[
            Text(
              'Available Roles (${_allRoles.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(context).size.height *
                    0.35, // Prevent it from taking the whole screen
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _allRoles.length,
                itemBuilder: (context, index) {
                  final role = _allRoles[index];
                  final permCount = [
                    role.canRead,
                    role.canGet,
                    role.canList,
                    role.canWrite,
                    role.canCreate,
                    role.canUpdate,
                    role.canDelete,
                  ].where((p) => p == true).length;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Theme(
                      // Removes the borders ExpansionTile adds by default
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          role.roleName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        subtitle: Text(
                          '$permCount permissions • Click to manage fields',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade400,
                          ),
                          onPressed: _isDeletingRole
                              ? null
                              : () => _deleteRole(role.roleName),
                          tooltip: 'Delete Role',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          20,
                        ),
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(),
                              const SizedBox(height: 8),
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('colleges')
                                    .doc(widget.collegeId)
                                    .collection('roles')
                                    .doc(role.roleName)
                                    .get(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  List<dynamic> fields = [];
                                  if (snapshot.hasData &&
                                      snapshot.data!.exists) {
                                    final data =
                                        snapshot.data!.data()
                                            as Map<String, dynamic>;
                                    fields = data['customFields'] ?? [];
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Custom Detail Fields for ${role.roleName}s:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (fields.isEmpty)
                                        Text(
                                          'No custom fields defined yet.',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: fields
                                              .map(
                                                (field) => Chip(
                                                  label: Text(field.toString()),
                                                  backgroundColor:
                                                      Colors.blue.shade50,
                                                  labelStyle: TextStyle(
                                                    color: Colors.blue.shade900,
                                                    fontSize: 13,
                                                  ),
                                                  side: BorderSide.none,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      const SizedBox(height: 16),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _showAddFieldDialog(role.roleName),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 20,
                                        ),
                                        label: const Text('Add Detail Field'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.blue.shade700,
                                          backgroundColor: Colors.blue.shade50,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
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
            const SizedBox(height: 32),
          ],

          // --- USER ASSIGNMENTS SECTION ---
          Text(
            'User Assignments (${displayedUsers.length})',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),

          // --- USERS LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayedUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_off_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No users found.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create users in User Management section.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: displayedUsers.length,
                    itemBuilder: (context, index) {
                      final user = displayedUsers[index];
                      final name = user['name'] ?? 'Unknown';
                      final email = user['email'] ?? 'No Email';
                      final uid = user['uid'];
                      final currentRole = user['role'];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.blue.shade50,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // --- ROLE DROPDOWN ---
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: currentRole == null
                                      ? Colors.orange.shade50
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: currentRole == null
                                        ? Colors.orange.shade200
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: currentRole,
                                    hint: Text(
                                      'Unassigned',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.unfold_more_rounded,
                                      color: Colors.grey.shade600,
                                      size: 20,
                                    ),
                                    style: TextStyle(
                                      color: currentRole == null
                                          ? Colors.orange.shade800
                                          : Colors.grey.shade800,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    items: roleNames.map((String? role) {
                                      return DropdownMenuItem<String?>(
                                        value: role,
                                        child: Text(role ?? 'Unassigned'),
                                      );
                                    }).toList(),
                                    onChanged: (String? newRole) {
                                      if (newRole != currentRole &&
                                          uid != null) {
                                        _changeUserRole(uid, name, newRole);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
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
