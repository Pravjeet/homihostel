import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';

class UserManagementView extends StatefulWidget {
  final String collegeId;

  const UserManagementView({super.key, required this.collegeId});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final FirebaseAuthService _authService = FirebaseAuthService();

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  String _selectedRole = 'Warden';

  bool _isLoading = false;

  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch users from Firebase (you'll need to implement this method)
      // For now, we'll use dummy data with updated names
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _users = [
          {'name': 'Deepak', 'email': 'deepak@example.com', 'role': 'Warden'},
          {
            'name': 'Rahul',
            'email': 'rahul@example.com',
            'role': 'Chief Warden',
          },
        ];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitUserInvitation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.registerSubUser(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        role: _selectedRole,
        parentCollegeId: widget.collegeId,
        isActive: true,
      );

      if (!mounted) return;

      // Clear form after successful creation
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      setState(() {
        _selectedRole = 'Warden';
      });

      // Reload users list
      await _loadUsers();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User created successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _resetForm() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _selectedRole = 'Warden';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title - No Add User Button Here
        const Text(
          'User Management',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 8),
        const Text(
          'Create and manage users for your institution',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),

        const SizedBox(height: 24),

        // Create User Form - Full width card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_add,
                        color: Colors.blueAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Create New User',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                          obscureText: true,
                          validator: (v) => v == null || v.length < 6
                              ? 'Minimum 6 characters'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Role',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.admin_panel_settings),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Warden',
                              child: Text('Warden'),
                            ),
                            DropdownMenuItem(
                              value: 'Chief Warden',
                              child: Text('Chief Warden'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedRole = value!;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submitUserInvitation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Create User',
                                style: TextStyle(color: Colors.white),
                              ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _isLoading ? null : _resetForm,
                        child: const Text('Clear Form'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Users List Section
        Row(
          children: [
            const Text(
              'Registered Users',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_users.length} users',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Users Table
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Create your first user using the form above',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 60,
                      headingRowColor: MaterialStateColor.resolveWith(
                        (states) => Colors.grey.shade50,
                      ),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'Name',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Email',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Role',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Actions',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      rows: _users.map((user) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.grey.shade200,
                                    child: Text(
                                      (user['name'] ?? '')[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(user['name'] ?? ''),
                                ],
                              ),
                            ),
                            DataCell(Text(user['email'] ?? '')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: user['role'] == 'Chief Warden'
                                      ? Colors.purple.shade100
                                      : Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  user['role'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: user['role'] == 'Chief Warden'
                                        ? Colors.purple.shade800
                                        : Colors.blue.shade800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      size: 20,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () {
                                      // Implement edit functionality
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Edit functionality coming soon',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      // Implement delete functionality
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Delete User'),
                                          content: Text(
                                            'Are you sure you want to delete ${user['name']}?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pop(context);
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Delete functionality coming soon',
                                                    ),
                                                    backgroundColor:
                                                        Colors.orange,
                                                  ),
                                                );
                                              },
                                              child: const Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
