import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'firebase_auth_service.dart'; // Ensure this path is correct in your project

class UserDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String collegeId;

  const UserDetailsScreen({
    super.key,
    required this.user,
    required this.collegeId,
  });

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  // final FirebaseAuthService _authService = FirebaseAuthService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;

  // Standard field controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  // Dynamic field controllers
  List<String> _roleCustomFields = [];
  final Map<String, TextEditingController> _customFieldControllers = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] ?? '');
    _phoneController = TextEditingController(
      text: widget.user['phoneNumber'] ?? '',
    );
    _loadRoleFields();
  }

  Future<void> _loadRoleFields() async {
    final role = widget.user['role'] ?? 'Unassigned';
    if (role == 'Unassigned') {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('colleges')
          .doc(widget.collegeId)
          .collection('roles')
          .doc(role)
          .get();

      if (doc.exists && doc.data()!.containsKey('customFields')) {
        _roleCustomFields = List<String>.from(doc.data()!['customFields']);
        Map<String, dynamic> userCustomData = widget.user['customData'] ?? {};

        for (String field in _roleCustomFields) {
          _customFieldControllers[field] = TextEditingController(
            text: userCustomData[field]?.toString() ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint("Error loading fields: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    Map<String, dynamic> updateData = {
      'name': _nameController.text.trim(),
      'phoneNumber': _phoneController.text.trim(),
    };

    Map<String, dynamic> customData = {};
    _customFieldControllers.forEach((fieldName, controller) {
      if (controller.text.trim().isNotEmpty) {
        customData[fieldName] = controller.text.trim();
      }
    });

    if (customData.isNotEmpty) {
      updateData['customData'] = customData;
    }

    try {
      // await _authService.updateUserDetails(widget.user['uid'], updateData);

      // Simulating network delay for demonstration
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User details updated successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    for (var controller in _customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // Helper method to generate avatar initials
  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    List<String> parts = name.trim().split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  // Helper method to guess appropriate icons for custom fields
  IconData _getIconForField(String fieldName) {
    final lower = fieldName.toLowerCase();
    if (lower.contains('date')) return Icons.calendar_today;
    if (lower.contains('id') || lower.contains('number')) return Icons.badge;
    if (lower.contains('dept') || lower.contains('department'))
      return Icons.domain;
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    final String role = widget.user['role'] ?? 'Unassigned';
    final String currentName = _nameController.text.isNotEmpty
        ? _nameController.text
        : (widget.user['name'] ?? 'Unknown User');

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'User Profile',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Header Section ---
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                            child: Text(
                              _getInitials(currentName),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            currentName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Chip(
                            label: Text(
                              role.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // --- Read-Only System Information ---
                    _buildSectionHeader('System Details'),
                    _buildCardWrapper(
                      child: Column(
                        children: [
                          _buildReadOnlyTile(
                            icon: Icons.fingerprint,
                            title: 'User ID',
                            subtitle: widget.user['uid'] ?? 'N/A',
                          ),
                          const Divider(height: 1),
                          _buildReadOnlyTile(
                            icon: Icons.email_outlined,
                            title: 'Email Address',
                            subtitle:
                                widget.user['email'] ?? 'No Email Provided',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Editable Personal Details ---
                    _buildSectionHeader('Personal Information'),
                    _buildCardWrapper(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Name cannot be empty'
                                  : null,
                              decoration: _buildInputDecoration(
                                'Full Name',
                                Icons.person_outline,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _buildInputDecoration(
                                'Phone Number',
                                Icons.phone_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- Dynamic Role Details ---
                    if (_roleCustomFields.isNotEmpty) ...[
                      _buildSectionHeader('$role Details'),
                      _buildCardWrapper(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children:
                                _roleCustomFields.map((field) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16.0,
                                      ),
                                      child: TextFormField(
                                        controller:
                                            _customFieldControllers[field],
                                        decoration: _buildInputDecoration(
                                          field,
                                          _getIconForField(field),
                                        ),
                                      ),
                                    );
                                  }).toList()
                                  ..removeLast(), // removes the padding from the last element
                          ),
                        ),
                      ),
                    ] else if (role != 'Unassigned') ...[
                      Center(
                        child: Text(
                          'No extra details required for $role.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // --- Save Button ---
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  // --- UI Helper Widgets ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCardWrapper({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  ListTile _buildReadOnlyTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.grey.shade700, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 15,
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey.shade500),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).primaryColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
