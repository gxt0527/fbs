import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/permission_guide_page.dart';
import 'pages/test_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_AppLauncher());
}

class FBSApp extends StatelessWidget {
  final bool showPermissionGuide;

  const FBSApp({super.key, this.showPermissionGuide = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FBS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C6FF7),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C6FF7),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      initialRoute: showPermissionGuide ? '/permission_guide' : '/',
      routes: {
        '/': (context) => const HomePage(),
        '/settings': (context) => const SettingsPage(),
        '/permission_guide': (context) => const PermissionGuidePage(),
        '/test': (context) => const TestPage(),
      },
    );
  }
}

class _AppLauncher extends StatefulWidget {
  @override
  State<_AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<_AppLauncher> {
  bool _showPermissionGuide = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool('permission_guide_completed') ?? false;
    if (mounted) {
      setState(() {
        _showPermissionGuide = !completed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return FBSApp(showPermissionGuide: _showPermissionGuide);
  }
}
