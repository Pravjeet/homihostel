import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';
import 'auth_gate.dart';
import 'user_management_view.dart';
import 'hostel_configuration_view.dart';
import 'roles_view.dart';

class SuperAdminDashboard extends StatefulWidget {
  final String institutionName;
  final String adminName;
  final String email;

  const SuperAdminDashboard({
    super.key,
    required this.institutionName,
    required this.adminName,
    required this.email,
  });

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  final FirebaseAuthService _authService = FirebaseAuthService();

  String collegeId = '';
  bool isLoading = true;

  // Key to access RolesView state and call refreshUsers
  final GlobalKey<RolesViewState> _rolesViewKey = GlobalKey<RolesViewState>();

  @override
  void initState() {
    super.initState();
    _loadCollegeId();
  }

  Future<void> _loadCollegeId() async {
    try {
      final profile = await _authService.getCurrentUserProfile();

      if (profile != null) {
        setState(() {
          collegeId = profile['collegeId'] ?? '';
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Callback that will be triggered when a user is created
  void _onUserCreated() {
    // Refresh the roles view to show the new user immediately
    _rolesViewKey.currentState?.refreshUsers();
  }

  Future<void> _logout() async {
    await _authService.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          // ===================================================
          // SIDEBAR - Fixed with Material widget
          // ===================================================
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 260 : 78,
            child: Material(
              color: const Color(0xFF1E293B),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 16,
                    ),
                    color: const Color(0xFF0F172A),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFF6366F1),
                          child: Icon(
                            Icons.admin_panel_settings,
                            color: Colors.white,
                          ),
                        ),
                        if (_isSidebarExpanded) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.institutionName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  widget.adminName,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        _buildSidebarTile(
                          index: 0,
                          label: 'User Management',
                          icon: Icons.person_add_alt_1_rounded,
                        ),
                        _buildSidebarTile(
                          index: 1,
                          label: 'Hostel Configuration',
                          icon: Icons.domain_rounded,
                        ),
                        _buildSidebarTile(
                          index: 2,
                          label: 'System Diagnostics',
                          icon: Icons.analytics_rounded,
                        ),
                        _buildSidebarTile(
                          index: 3,
                          label: 'Roles',
                          icon: Icons.shield_rounded,
                        ),
                        _buildSidebarTile(
                          index: 4,
                          label: 'Permissions',
                          icon: Icons.vpn_key_rounded,
                        ),
                      ],
                    ),
                  ),

                  Divider(color: Colors.white.withOpacity(0.1)),

                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                    ),
                    title: _isSidebarExpanded
                        ? const Text(
                            'Logout',
                            style: TextStyle(color: Colors.white54),
                          )
                        : null,
                    onTap: _logout,
                  ),

                  ListTile(
                    leading: Icon(
                      _isSidebarExpanded
                          ? Icons.arrow_back_ios_new_rounded
                          : Icons.arrow_forward_ios_rounded,
                      color: Colors.white54,
                    ),
                    title: _isSidebarExpanded
                        ? const Text(
                            'Collapse',
                            style: TextStyle(color: Colors.white54),
                          )
                        : null,
                    onTap: () {
                      setState(() {
                        _isSidebarExpanded = !_isSidebarExpanded;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // ===================================================
          // CONTENT AREA
          // ===================================================
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Index 0: User Management (Updated with callback)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: UserManagementView(
                    collegeId: collegeId,
                    onUserCreated: _onUserCreated, // Pass callback
                  ),
                ),
                // Index 1: Hostel Configuration
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: HostelConfigurationView(collegeId: collegeId),
                ),
                // Index 2: System Diagnostics
                const Center(child: Text('System Diagnostics Module')),

                // Index 3: Roles (Updated with key for refreshing)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: RolesView(
                    key: _rolesViewKey, // Key to access state for refreshing
                    collegeId: collegeId,
                  ),
                ),

                // Index 4: Permissions
                const Center(child: Text('Permissions Module')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTile({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: const Color(0xFF6366F1).withOpacity(0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF6366F1) : Colors.white60,
        ),
        title: _isSidebarExpanded
            ? Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              )
            : null,
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
