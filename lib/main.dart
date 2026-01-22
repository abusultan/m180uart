import 'package:flutter/material.dart';
import 'ui/screens/login_screen.dart';

void main() {
  runApp(const CutterApp());
}

class CutterApp extends StatelessWidget {
  const CutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YousefCutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
