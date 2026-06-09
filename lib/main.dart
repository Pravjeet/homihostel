import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
// Import our new intermediate workspace gate

void main() {
  runApp(const HostelAdminApp());
}

class HostelAdminApp extends StatelessWidget {
  const HostelAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HMS Admin Console',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // 3-Second boot sequence simulation
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // Jumps straight to the intermediate Auth Gate screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthGateScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.blueAccent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TODO: Replace with custom asset image later
            Icon(Icons.home_work, size: 100, color: Colors.white),

            SizedBox(height: 20),

            Text(
              'HomiHostel', // Capitalized both 'H's here
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
