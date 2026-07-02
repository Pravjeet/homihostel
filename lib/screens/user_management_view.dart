import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_auth_service.dart';
import 'add_user_screen.dart';
import 'user_details_screen.dart'; // Added import for the new screen

class UserManagementView extends StatefulWidget {
  final String collegeId;
  final VoidCallback? onUserCreated;

  const UserManagementView({
    super.key,
    required this.collegeId,
    this.onUserCreated,
  });

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  String _selectedRoleFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final fetchedUsers = await _authService.getUsersByCollegeId(
        widget.collegeId,
      );
      if (!mounted) return;
      setState(() {
        _users = fetchedUsers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load users: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _openAddUserScreen() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddUserScreen(
          collegeId: widget.collegeId,
          onUserCreated: widget.onUserCreated,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      _loadUsers();
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    var filtered = List<Map<String, dynamic>>.from(_users);
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final name = (user['name'] ?? '').toString().toLowerCase();
        final email = (user['email'] ?? '').toString().toLowerCase();
        final phone = (user['phoneNumber'] ?? '').toString().toLowerCase();
        final query = _searchQuery.toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // Apply role filter
    if (_selectedRoleFilter != 'All') {
      filtered = filtered
          .where(
            (user) => (user['role'] ?? 'Unassigned') == _selectedRoleFilter,
          )
          .toList();
    }

    // Sort by creation date (newest first)
    filtered.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return filtered;
  }

  List<String> get _availableRoles {
    final roles = _users
        .where((u) => u['role'] != null)
        .map((u) => u['role'].toString())
        .toSet()
        .toList();
    roles.sort();
    return ['All', ...roles];
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _filteredUsers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User Management',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Manage all users in one place. Control access, assign roles, and monitor activity across your platform.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                // Refresh button
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
                    onPressed: _isLoading ? null : _loadUsers,
                    tooltip: 'Refresh Data',
                  ),
                ),
                const SizedBox(width: 12),
                // Add User button
                ElevatedButton.icon(
                  onPressed: _openAddUserScreen,
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  label: const Text(
                    'Add User',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Search and Filter bar
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search users by name, email, or phone...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Role filter dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: DropdownButton<String>(
                value: _selectedRoleFilter,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedRoleFilter = newValue;
                    });
                  }
                },
                underline: const SizedBox.shrink(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                icon: Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
                items: _availableRoles.map((String role) {
                  return DropdownMenuItem<String>(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Stats row
        Row(
          children: [
            _buildStatChip('Total Users', filteredUsers.length, Colors.blue),
          ],
        ),

        const SizedBox(height: 16),

        // Table with scroll
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredUsers.isEmpty
              ? _buildEmptyState()
              : Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width - 48,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _buildHeaderCell('Name', flex: 6),
                                  _buildHeaderCell('Email', flex: 6),
                                  _buildHeaderCell('Phone', flex: 4),
                                  _buildHeaderCell('Role', flex: 3),
                                  _buildHeaderCell('Joined', flex: 3),
                                  _buildHeaderCell('Last Active', flex: 3),
                                  _buildHeaderCell(
                                    'Actions',
                                    flex: 2,
                                    center: true,
                                  ),
                                ],
                              ),
                            ),
                            // Table Body
                            Expanded(
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: filteredUsers.length,
                                itemBuilder: (context, index) {
                                  final user = filteredUsers[index];
                                  return _buildTableRow(user, index);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        const SizedBox(height: 12),

        // Pagination info
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Showing ${filteredUsers.length} of ${_users.length} users',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1, bool center = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: Colors.grey.shade700,
          letterSpacing: 0.3,
        ),
        textAlign: center ? TextAlign.center : TextAlign.left,
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> user, int index) {
    final name = user['name'] ?? 'Unknown';
    final email = user['email'] ?? 'No Email';
    final phoneNumber = user['phoneNumber'] ?? '—';
    final role = user['role'] ?? 'Unassigned';
    final joinedDate = user['createdAt'] != null
        ? _formatDate(user['createdAt'])
        : '—';
    final lastActive = user['lastActive'] != null
        ? _formatDate(user['lastActive'])
        : '—';

    return Material(
      color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
      child: InkWell(
        hoverColor: Colors.blue.shade50.withOpacity(0.5),
        onTap: () async {
          // Navigate to User Details Screen
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  UserDetailsScreen(user: user, collegeId: widget.collegeId),
            ),
          );
          // If the user was updated, refresh the list
          if (result == true) {
            _loadUsers();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade100, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Name with avatar
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue.shade50,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          color: Colors.grey.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Email
              Expanded(
                flex: 6,
                child: Text(
                  email,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Phone
              Expanded(
                flex: 4,
                child: Text(
                  phoneNumber,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Role
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: role == 'Unassigned'
                        ? Colors.orange.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: role == 'Unassigned'
                          ? Colors.orange.shade800
                          : Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // Joined Date
              Expanded(
                flex: 3,
                child: Text(
                  joinedDate,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
              // Last Active
              Expanded(
                flex: 3,
                child: Text(
                  lastActive,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ),
              // Actions
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Keeping edit button for fast actions, but it's redundant now
                    IconButton(
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserDetailsScreen(
                              user: user,
                              collegeId: widget.collegeId,
                            ),
                          ),
                        );
                        if (result == true) {
                          _loadUsers();
                        }
                      },
                      tooltip: 'Edit user',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red.shade400,
                      ),
                      onPressed: () => _showDeleteConfirmation(user),
                      tooltip: 'Delete user',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedRoleFilter != 'All'
                ? 'Try adjusting your filters'
                : 'Tap "Add User" to create your first user.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '—';
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return '${_monthAbbr(date.month)} ${date.day}, ${date.year}';
      }
      return '—';
    } catch (e) {
      return '—';
    }
  }

  String _monthAbbr(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  void _showDeleteConfirmation(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to delete "${user['name']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _authService.deleteUser(user['uid']);
                _loadUsers();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete user: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
