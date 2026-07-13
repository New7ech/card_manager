import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'core/services/auth_service.dart';
import 'core/services/database_service.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize local JSON database for activity logs.
  await DatabaseService.instance.init();

  runApp(const CardManagerApp());
}

class CardManagerApp extends StatelessWidget {
  const CardManagerApp({super.key});

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
      home: StreamBuilder<firebase_auth.User?>(
        stream: firebase_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (_, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          if (snapshot.data == null) {
            return const LoginScreen();
          }

          return FutureBuilder<User?>(
            future: AuthService.instance.checkSession(),
            builder: (_, sessionSnapshot) {
              if (sessionSnapshot.connectionState != ConnectionState.done) {
                return _buildLoadingScreen();
              }

              return sessionSnapshot.data != null
                  ? const MainMenuScreen()
                  : const LoginScreen();
            },
          );
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
