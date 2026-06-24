import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';

class RolesView extends StatefulWidget {
  final String collegeId;

  const RolesView({super.key, required this.collegeId});

  @override
  State<RolesView> createState() => RolesViewState(); // Changed to public state class
}

// Made state class public so parent can access refreshUsers method
class RolesViewState extends State<RolesView> {
  final FirebaseAuthService _authService = FirebaseAuthService();

  bool _isLoading = false;
  List<Map<String, dynamic>> _allUsers = [];

  // Strictly the roles you want to assign via this UI
  final List<String?> _availableRoles = [
    null, // Represents "Unassigned"
    'Student',
    'Warden',
    'Chief Warden',
  ];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  // Public method that parent widget can call to refresh users
  Future<void> refreshUsers() async {
    await _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final fetchedUsers = await _authService.getUsersByCollegeId(
        widget.collegeId,
      );

      setState(() {
        _allUsers = fetchedUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _changeUserRole(
    String uid,
    String userName,
    String? newRole,
  ) async {
    // Optimistic UI update for immediate feedback
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
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Revert if it fails
      setState(() {
        _allUsers = previousUsers;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update role: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Completely hide SuperAdmins from this management screen
    final displayedUsers = _allUsers
        .where((u) => u['role'] != 'SuperAdmin')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Role Assignments',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Assign permissions and titles to registered users',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
            // Refresh Button
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blueAccent),
              onPressed: refreshUsers, // Changed to use public method
              tooltip: 'Refresh Users',
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Users List
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
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No users found.',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
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

                    // The raw role from the database
                    final rawRole = user['role'];

                    // 2. CRASH PREVENTION: If a role is in the database but not in our
                    // _availableRoles list, force the UI to display it as 'Unassigned'.
                    final safeRole = _availableRoles.contains(rawRole)
                        ? rawRole
                        : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue.shade50,
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    email,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Role Dropdown
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: safeRole == null
                                    ? Colors.orange.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: safeRole == null
                                      ? Colors.orange.shade200
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: safeRole, // Using the crash-safe role
                                  hint: const Text('Unassigned'),
                                  icon: const Icon(Icons.arrow_drop_down),
                                  style: TextStyle(
                                    color: safeRole == null
                                        ? Colors.orange.shade800
                                        : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  items: _availableRoles.map((String? role) {
                                    return DropdownMenuItem<String?>(
                                      value: role,
                                      child: Text(role ?? 'Unassigned'),
                                    );
                                  }).toList(),
                                  onChanged: (String? newRole) {
                                    if (newRole != rawRole && uid != null) {
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
    );
  }
}
