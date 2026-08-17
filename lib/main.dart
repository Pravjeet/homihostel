import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'firebase_options.dart';
import 'models/college_settings.dart' show AppBrightnessX;
import 'screens/auth_gate.dart';
import 'services/theme_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard the init so a misconfigured firebase_options file produces a
  // readable screen instead of a blank one.
  Object? startupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Local cache on, and uncapped.
    //
    // Firestore bills per document read, and the free tier allows 50,000 a
    // day — which a few thousand students burn through fast. With persistence
    // the SDK keeps a local copy and re-attaches listeners using a resume
    // token, so a reload asks "what changed?" instead of paying for the whole
    // roster again. The default cache is 40 MB, small enough that the roster
    // could be evicted between visits and re-fetched in full; unlimited keeps
    // it. Must be set before Firestore is used for anything.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Sign-in lasts as long as the tab, not the browser profile.
    //
    // Firebase's web default is LOCAL — the session survives closing the
    // browser entirely, so opening the app link lands you back in whoever
    // signed in last. On the shared office machines this runs on, that hands
    // the next person a live warden session. SESSION scopes the credential to
    // the tab: close it and the next visit starts at the login screen, while
    // an accidental F5 mid-task still keeps you signed in.
    //
    // Web-only in FlutterFire — it throws on Windows and Android, where the
    // OS account model already isolates users.
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
    }
  } catch (e) {
    startupError = e;
  }

  // Apply the workspace's last-known theme before the first frame, so the
  // login screen matches instead of showing the hardcoded default. AuthGate
  // re-applies the authoritative copy from Firestore the moment it loads
  // (see PaletteScope in auth_gate.dart) and refreshes this cache for next
  // time.
  final cachedTheme = await ThemeCache.instance.read();
  AppColors.apply(
    accent: cachedTheme.seed,
    dark: cachedTheme.brightness.isDark(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    ),
  );

  runApp(HostelApp(startupError: startupError));
}

class HostelApp extends StatelessWidget {
  final Object? startupError;
  const HostelApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Homi Hostel',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: startupError == null
          ? const AuthGate()
          : _StartupError(error: startupError!),
    );
  }
}

class _StartupError extends StatelessWidget {
  final Object error;
  const _StartupError({required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AppCard(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.danger),
              const SizedBox(height: 16),
              const Text(
                'Could not connect to Firebase',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
