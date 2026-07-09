import 'package:flutter/material.dart';
import 'core/services/database_service.dart';
import 'core/services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/admin_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize local JSON database
  await DatabaseService.instance.init();

  // Check if session is active
  final currentUser = await AuthService.instance.checkSession();
  runApp(CardManagerApp(initialUser: currentUser));
}

class CardManagerApp extends StatelessWidget {
  final User? initialUser;

  const CardManagerApp({super.key, this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion de Cartes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Sleek, premium deep blue
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFF10B981),
        ),
        useMaterial3: true,
      ),
      home: initialUser != null
          ? const MainMenuScreen()
          : (!DatabaseService.instance.hasUsers()
                ? const AdminSetupScreen()
                : const LoginScreen()),
      debugShowCheckedModeBanner: false,
    );
  }
}
