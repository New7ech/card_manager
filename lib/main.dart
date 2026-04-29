import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const CardManagerApp());
}

class CardManagerApp extends StatelessWidget {
  const CardManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
