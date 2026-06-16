import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';
import 'auth_gate.dart';
// Import your module views here when ready, e.g.:
// import 'student_management_view.dart';

class ChiefWardenDashboard extends StatefulWidget {
  final String institutionName;
  final String wardenName;
  final String email;

  const ChiefWardenDashboard({
    super.key,
    required this.institutionName,
    required this.wardenName,
    required this.email,
  });

  @override
  State<ChiefWardenDashboard> createState() => _ChiefWardenDashboardState();
}

class _ChiefWardenDashboardState extends State<ChiefWardenDashboard> {
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
                        backgroundColor: Color(
                          0xFF10B981,
                        ), // Changed to a distinct green for Warden
                        child: Icon(
                          Icons
                              .shield_rounded, // Changed icon to represent Warden
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
                        label: 'Student Overview',
                        icon: Icons.groups_rounded,
                      ),
                      _buildSidebarTile(
                        index: 1,
                        label: 'Room Allocation',
                        icon: Icons.meeting_room_rounded,
                      ),
                      _buildSidebarTile(
                        index: 2,
                        label: 'Leave & Gatepasses',
                        icon: Icons.transfer_within_a_station_rounded,
                      ),
                      _buildSidebarTile(
                        index: 3,
                        label: 'Complaints',
                        icon: Icons.report_problem_rounded,
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

          // ===================================================
          // CONTENT AREA
          // ===================================================
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Replace these Center placeholders with your actual view components
                const Center(child: Text('Student Overview Module')),
                const Center(child: Text('Room Allocation Module')),
                const Center(child: Text('Leave & Gatepasses Module')),
                const Center(child: Text('Complaints Module')),
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
        selectedTileColor: const Color(
          0xFF10B981,
        ).withOpacity(0.15), // Matched highlight color
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF10B981) : Colors.white60,
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
