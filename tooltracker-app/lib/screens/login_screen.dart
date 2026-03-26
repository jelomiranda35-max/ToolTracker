import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'admin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );

    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', result['user_id']);
      await prefs.setString('user_name', result['name']);
      await prefs.setString('username', result['username']);
      await prefs.setString('user_role', result['role'] ?? 'staff');

      final loginActor = result['name'] ?? result['username'];
      await DBHelper.instance.logActivity(
        eventType: 'login',
        eventDetail: 'User logged in',
        actor: loginActor,
      );
      
      if (mounted) {
        final role = result['role'] ?? 'staff';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                role == 'admin' ? const AdminScreen() : const HomeScreen(),
          ),
        );
      }
    } else {
      setState(() {
        _loading = false;
        _error = 'Invalid username or password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A3A5C),
                  border: Border.all(
                      color: const Color(0xFFF5A623).withOpacity(0.5),
                      width: 2),
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
              const SizedBox(height: 24),
              const Text('AMTEC',
                  style: TextStyle(
                      color: Color(0xFFF5A623),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6)),
              const Text('Tool Tracker',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      letterSpacing: 2)),
              const SizedBox(height: 48),
              // Username
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDeco('Username', Icons.alternate_email),
              ),
              const SizedBox(height: 14),
              // Password
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => _login(),
                decoration: _inputDeco(
                        'Password', Icons.lock)
                    .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.white38,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ]),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A623),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('SIGN IN',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),
              const Text('Agricultural Machinery Testing\nand Evaluation Center, UPLB',
                  style: TextStyle(
                      color: Colors.white24,
                      fontSize: 11,
                      height: 1.6),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: const Color(0xFFF5A623)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFF5A623)),
        ),
        filled: true,
        fillColor: const Color(0xFF1A3A5C),
      );
}