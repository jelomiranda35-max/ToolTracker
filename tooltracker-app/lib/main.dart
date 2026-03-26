import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'services/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  SyncService.instance.startListening();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const ToolTrackerApp(),
    ),
  );
}

class ToolTrackerApp extends StatelessWidget {
  const ToolTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMTEC: Tool Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1B2A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF5A623),
          surface: Color(0xFF1A3A5C),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<SharedPreferences> _prefsFuture;

  @override
  void initState() {
    super.initState();
    _prefsFuture = _loadAndSync();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: _prefsFuture,
      builder: (context, snapshot) {
        // ── Splash screen ────────────────────────────────────────────────────
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D1B2A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // AMTEC logo in circular frame
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A3A5C),
                      border: Border.all(
                        color: const Color(0xFFF5A623).withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/amtec_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.construction,
                          color: Color(0xFFF5A623),
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'AMTEC',
                    style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tool Tracker',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 36),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFFF5A623),
                      strokeWidth: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return const LoginScreen();
        }

        final prefs = snapshot.data!;
        final userId = prefs.getInt('user_id');

        if (userId == null) return const LoginScreen();

        final role = prefs.getString('user_role') ?? 'staff';
        return role == 'admin' ? const AdminScreen() : const HomeScreen();
      },
    );
  }

  Future<SharedPreferences> _loadAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt('user_id') != null) {
      SyncService.instance.syncAll();
    }
    return prefs;
  }
}