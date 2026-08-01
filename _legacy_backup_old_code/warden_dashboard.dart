import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';
import 'auth_gate.dart';
import 'user_management_view.dart';
import 'hostel_configuration_view.dart';

class WardenDashboard extends StatefulWidget {
  final String institutionName;
  final String wardenName;
  final String email;

  const WardenDashboard({
    super.key,
    required this.institutionName,
    required this.wardenName,
    required this.email,
  });

  @override
  State<WardenDashboard> createState() => _WardenDashboardState();
}

class _WardenDashboardState extends State<WardenDashboard> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  final FirebaseAuthService _authService = FirebaseAuthService();

  String collegeId = '';
  bool isLoading = true;

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
          // SIDEBAR
          // ===================================================
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 260 : 78,
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
                          Icons.badge_rounded, // Distinct icon for the Warden
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
                                widget.wardenName,
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
                    ],
                  ),
                ),

                Divider(color: Colors.white.withValues(alpha: 0.1)),

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

          // ===================================================
          // CONTENT AREA
          // ===================================================
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Index 0: User Management
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: UserManagementView(collegeId: collegeId),
                ),
                // Index 1: Hostel Configuration
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: HostelConfigurationView(collegeId: collegeId),
                ),
                // Index 2: System Diagnostics
                const Center(child: Text('System Diagnostics Module')),
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
        selectedTileColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
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
