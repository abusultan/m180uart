import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/rep_main_screen.dart';
import 'services/api_service.dart';
import 'providers/language_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (context) => LanguageProvider(),
      child: const CutterApp(),
    ),
  );
}

class CutterApp extends StatelessWidget {
  const CutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageProvider>(
      builder: (context, languageProvider, child) {
        return MaterialApp(
          title: 'Anticrash',
          debugShowCheckedModeBanner: false,
          locale: languageProvider
              .locale, // This might be null, which is fine (uses system default)
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00FF88),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'), // English
            Locale('ar'), // Arabic
          ],
          home: const SplashScreen(),
        );
      },
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await ApiService().loadToken();
    final prefs = await SharedPreferences.getInstance();
    final isRepMode = prefs.getBool('mock_rep_mode') ?? false;
    if (token != null && token.isNotEmpty) {
      // Valid token found, try to get user info
      final user = await ApiService().getUserInfo();
      if (user != null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                isRepMode ? const RepMainScreen() : const MainScreen(),
          ),
        );
        return;
      }
    }

    // No valid token or user info fetch failed
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00FF88))),
    );
  }
}
