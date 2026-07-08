import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FBSApp());
}

class FBSApp extends StatelessWidget {
  const FBSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FBS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7C6FF7), useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF7C6FF7), useMaterial3: true, brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
}
