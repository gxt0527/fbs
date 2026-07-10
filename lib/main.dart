import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/permission_guide_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FBSApp());
}

class FBSApp extends StatelessWidget {
  const FBSApp({super.key});

  static const _keyCompleted = 'permission_guide_completed';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SharedPreferences.getInstance().then((p) => p.getBool(_keyCompleted) ?? false),
      builder: (context, snapshot) {
        final completed = snapshot.data ?? false;
        return MaterialApp(
          title: 'FBS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF7C6FF7), useMaterial3: true, brightness: Brightness.light),
          darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF7C6FF7), useMaterial3: true, brightness: Brightness.dark),
          themeMode: ThemeMode.system,
          home: completed ? const HomePage() : const PermissionGuidePage(),
          routes: {'/settings': (context) => const SettingsPage()},
        );
      },
    );
  }
}
