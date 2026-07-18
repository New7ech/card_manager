import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

              final sessionUser = sessionSnapshot.data;
              return sessionUser != null
                  ? _BlockWatcher(
                      uid: sessionUser.id,
                      child: const MainMenuScreen(),
                    )
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

class _BlockWatcher extends StatefulWidget {
  final String uid;
  final Widget child;

  const _BlockWatcher({required this.uid, required this.child});

  @override
  State<_BlockWatcher> createState() => _BlockWatcherState();
}

class _BlockWatcherState extends State<_BlockWatcher> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _isHandlingAccountClosure = false;

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  @override
  void didUpdateWidget(covariant _BlockWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _subscription?.cancel();
      _isHandlingAccountClosure = false;
      _startWatching();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startWatching() {
    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots()
        .listen(_handleProfileSnapshot, onError: (_) {});
  }

  Future<void> _handleProfileSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_isHandlingAccountClosure) return;

    final status = snapshot.data()?['status']?.toString();
    if (snapshot.exists && status == 'active') return;

    _isHandlingAccountClosure = true;
    LoginScreenNotice.showOnNextBuild(_accountClosureMessage(snapshot, status));
    await AuthService.instance.logout();
  }

  String _accountClosureMessage(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String? status,
  ) {
    if (!snapshot.exists || status == 'deleted') {
      return 'Compte supprime par un administrateur.';
    }
    if (status == 'blocked') {
      return 'Compte bloque par un administrateur.';
    }
    return 'Compte desactive par un administrateur.';
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
