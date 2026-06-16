import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // ADD THIS IMPORT
import 'firebase_options.dart'; // ADD THIS IMPORT
import 'screens/auth_gate.dart';

// Change main() to be an asynchronous function
void main() async {
  // 1. You MUST add this line whenever main() is async
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Turn on Firebase using the options file you generated
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
            Icon(Icons.home_work, size: 100, color: Colors.white),

            SizedBox(height: 20),

            Text(
              'HomiHostel',
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
