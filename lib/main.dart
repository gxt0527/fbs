import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/home_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';
import 'pages/permission_guide_page.dart';
import 'services/native_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化分享/复制菜单回调监听
  NativeService().initShareListener();
  runApp(const FBSApp());
}

/// LiquidGlass 设计令牌 — 来自 AndroidLiquidGlass (Backdrop) 设计语言
class GlassTokens {
  GlassTokens._();

  // ── 强调色 ──
  static const accent = Color(0xFF0088FF);
  static const accentDark = Color(0xFF0091FF);

  // ── 玻璃容器色 (叠加在模糊之上) ──
  static const glassLight = Color(0x66FAFAFA); // 40% opacity
  static const glassDark = Color(0x66121212);

  // ── 玻璃边框 ──
  static const borderLight = Color(0x1AFFFFFF);
  static const borderDark = Color(0x1AFFFFFF);

  // ── 阴影 ──
  static List<BoxShadow> glassShadow(Brightness brightness) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
    if (brightness == Brightness.dark)
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
  ];

  // ── 内发光（用渐变模拟玻璃高光边缘） ──
  static BoxDecoration glassDecoration(Brightness brightness, {double radius = 20}) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.25),
        width: 0.5,
      ),
      boxShadow: glassShadow(brightness),
    );
  }

  // ── 玻璃容器渐变背景 ──
  static LinearGradient glassGradient(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
        ? [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.03)]
        : [Colors.white.withValues(alpha: 0.50), Colors.white.withValues(alpha: 0.25)],
    );
  }

  // ── 圆角规范 ──
  static const double radiusXS = 8;
  static const double radiusSM = 12;
  static const double radiusMD = 16;
  static const double radiusLG = 20;
  static const double radiusXL = 24;
  static const double radiusFull = 999; // 胶囊

  // ── 间距规范 (8dp 网格) ──
  static const double spaceXS = 4;
  static const double spaceSM = 8;
  static const double spaceMD = 16;
  static const double spaceLG = 24;
  static const double spaceXL = 32;
}

/// 玻璃容器辅助组件
class GlassSurface extends StatelessWidget {
  final Widget? child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final Color? customColor;

  const GlassSurface({
    super.key,
    this.child,
    this.borderRadius = GlassTokens.radiusLG,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.onTap,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        margin: margin,
        padding: padding ?? const EdgeInsets.all(GlassTokens.spaceMD),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: customColor != null
            ? null
            : GlassTokens.glassGradient(brightness),
          color: customColor,
          border: Border.all(
            color: brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.30),
            width: 0.5,
          ),
          boxShadow: GlassTokens.glassShadow(brightness),
        ),
        child: child,
      ),
    );

    return surface;
  }
}

class FBSApp extends StatelessWidget {
  const FBSApp({super.key});

  static const _keyCompleted = 'permission_guide_completed_v2';

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = isDark ? GlassTokens.accentDark : GlassTokens.accent;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF0F2F5),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF0F2F5),
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTokens.radiusLG)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _SlideBackTransitionBuilder(),
        },
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.50),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTokens.radiusFull)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTokens.radiusFull)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTokens.radiusFull)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.60),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTokens.radiusFull)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: SharedPreferences.getInstance().then((p) => p.getBool(_keyCompleted) ?? false),
      builder: (context, snapshot) {
        final completed = snapshot.data ?? false;
        return MaterialApp(
          title: 'FBS',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: ThemeMode.system,
          home: completed ? const MainScaffold() : const PermissionGuidePage(),
        );
      },
    );
  }
}

/// 主框架 — 底部导航栏 (首页 / 记录 / 设置)
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final _historyKey = GlobalKey<HistoryPageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePage(),
      HistoryPage(key: _historyKey),
      const SettingsPage(),
    ];
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    // 切换到记录页时刷新数据
    if (index == 1) {
      _historyKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            backgroundColor:
                isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF0F2F5),
            selectedItemColor: GlassTokens.accent,
            unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history_rounded),
                label: '记录',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 滑动转场 — 从右滑入，返回时左滑出
class _SlideBackTransitionBuilder extends PageTransitionsBuilder {
  const _SlideBackTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    );
  }
}
