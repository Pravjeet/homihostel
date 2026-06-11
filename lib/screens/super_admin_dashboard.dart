import 'package:flutter/material.dart';
import 'user_management_view.dart'; // Ensure this matches your file path structure

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
  int _selectedIndex = 0; // Default open screen: User Management Matrix
  bool _isSidebarExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          // ===================================================================
          // LEFT SIDEBAR RAIL NAVIGATION PANEL
          // ===================================================================
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isSidebarExpanded ? 260 : 78,
            color: const Color(0xFF1E293B), // Premium Dark Slate Base
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Workspace Profiler Banner Zone
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
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                widget.adminName,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Functional Options Menu Tiles
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      _buildSidebarTile(
                        index: 0,
                        label: 'Add New User',
                        icon: Icons.person_add_alt_1_rounded,
                      ),
                      _buildSidebarTile(
                        index: 1,
                        label: 'Hostel Matrix Config',
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

                // Exit / Collapse Interaction Triggers
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                ListTile(
                  horizontalTitleGap: 12,
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  title: _isSidebarExpanded
                      ? const Text(
                          'Logout Console',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        )
                      : null,
                  onTap: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
                ListTile(
                  horizontalTitleGap: 12,
                  leading: Icon(
                    _isSidebarExpanded
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: Colors.white54,
                    size: 16,
                  ),
                  title: _isSidebarExpanded
                      ? const Text(
                          'Collapse Bar',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        )
                      : null,
                  onTap: () =>
                      setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                ),
              ],
            ),
          ),

          // ===================================================================
          // RIGHT SIDE DYNAMIC CONTENT VIEWPORT
          // ===================================================================
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Embed your custom view safely into the stack frame layout
                Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: const UserManagementView(),
                ),
                const Center(
                  child: Text(
                    'Hostel Configuration & Infrastructure Control Board View',
                  ),
                ),
                const Center(
                  child: Text(
                    'Global System Diagnostics & Analytical Flow Engine View',
                  ),
                ),
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
        horizontalTitleGap: 12,
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF6366F1) : Colors.white60,
          size: 22,
        ),
        title: _isSidebarExpanded
            ? Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              )
            : null,
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }
}
