import 'package:flutter/material.dart';
import 'firebase_auth_service.dart';

// Dashboard Imports
import 'super_admin_dashboard.dart';
import 'chief_warden_dashboard.dart';
import 'warden_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FirebaseAuthService _authService = FirebaseAuthService();

  bool _isPasswordHidden = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // 1. Basic form validation
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 2. Start Loading State
    setState(() {
      _isLoading = true;
    });

    try {
      // 3. Call the Auth Service to Login and fetch the user profile map
      final userProfile = await _authService.loginUser(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Check if widget is still in the tree before navigating
      if (!mounted) return;

      if (userProfile != null) {
        // 4. Extract the role
        final String role = userProfile['role'] ?? 'Unknown';

        // Extract common data for the dashboards
        final String institutionName =
            userProfile['institutionName'] ?? 'Institution';
        final String userName = userProfile['name'] ?? 'User';
        final String userEmail =
            userProfile['email'] ?? _emailController.text.trim();

        // 5. Route based on role
        if (role == 'SuperAdmin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SuperAdminDashboard(
                institutionName: institutionName,
                adminName: userName,
                email: userEmail,
              ),
            ),
          );
        } else if (role == 'Chief Warden') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChiefWardenDashboard(
                institutionName: institutionName,
                wardenName: userName,
                email: userEmail,
              ),
            ),
          );
        } else if (role == 'Warden') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => WardenDashboard(
                institutionName: institutionName,
                wardenName: userName,
                email: userEmail,
              ),
            ),
          );
        } else {
          _showErrorSnackBar('Access Denied: Unrecognized or Unassigned Role.');
        }
      }
    } catch (e) {
      // Show error from Firebase if login fails
      if (mounted) {
        _showErrorSnackBar(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      // Stop Loading State
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
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
            width: 450,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
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
                  const Icon(
                    Icons.lock_person_rounded,
                    size: 50,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Workspace Sign In',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Access your institutional administration control console.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const Divider(height: 32),

                  // EMAIL FIELD
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Account Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Color(0xFFF8F9FA),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // PASSWORD FIELD
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isPasswordHidden,
                    decoration: InputDecoration(
                      labelText: 'Workspace Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      filled: true,
                      fillColor: const Color(0xFFF8F9FA),
                      border: const OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordHidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordHidden = !_isPasswordHidden;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // SUBMIT BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor: Colors.blueAccent.withOpacity(
                          0.6,
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Enter Console Workspace',
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
}
