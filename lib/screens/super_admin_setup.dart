import 'package:flutter/material.dart';

// 1. THE PUBLIC STATEFUL WIDGET PIPELINE
class SuperAdminSetupScreen extends StatefulWidget {
  const SuperAdminSetupScreen({super.key});

  @override
  State<SuperAdminSetupScreen> createState() => _SuperAdminSetupScreenState();
}

// 2. THE PRIVATE IMPLEMENTATION HOLDER
class _SuperAdminSetupScreenState extends State<SuperAdminSetupScreen> {
  // Global key to validate form rules before processing strings
  final _formKey = GlobalKey<FormState>();

  // Text controllers to capture active field states
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordHidden = true;

  @override
  void dispose() {
    // Memory Management: Safely dump tracking pipelines when exiting
    _institutionController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleRegistrationSubmit() {
    if (_formKey.currentState!.validate()) {
      String instName = _institutionController.text.trim();
      String adminName = _adminNameController.text.trim();
      String email = _emailController.text.trim();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Registration Form Data Captured'),
          content: Text(
            'Institution: $instName\n'
            'Super Admin: $adminName\n'
            'Email: $email\n\n'
            'Next step: We will handle background logic to generate '
            'the hidden abstract ID and push this to Firestore!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Excellent'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.add_business_rounded,
                        size: 36,
                        color: Colors.blueAccent,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Register New Institution',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Setup a completely isolated cloud instance for your hostel network.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const Divider(height: 32),

                  const Text(
                    'ORGANIZATION DETAILS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _institutionController,
                    decoration: _buildInputDecoration(
                      'Institution / College Name',
                      Icons.account_balance_rounded,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your institution name';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'SUPER ADMIN SYSTEM ACCOUNT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _adminNameController,
                    decoration: _buildInputDecoration(
                      'Full Name of Admin',
                      Icons.person_outline_rounded,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please specify the master administrator name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _buildInputDecoration(
                      'Master Admin Email ID',
                      Icons.email_outlined,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'An operational email is required';
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value.trim())) {
                        return 'Please provide a valid email format structure';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isPasswordHidden,
                    decoration: InputDecoration(
                      labelText: 'Create Console Password',
                      prefixIcon: const Icon(
                        Icons.lock_outlined,
                        size: 20,
                        color: Colors.black45,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordHidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordHidden = !_isPasswordHidden;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FA),
                      labelStyle: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Security password cannot be blank';
                      }
                      if (value.length < 6) {
                        return 'Password must contain at least 6 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _handleRegistrationSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Initialize Workspace Instance',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: Colors.black45),
      filled: true,
      fillColor: const Color(0xFFF8F9FA),
      labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }
}
