import 'package:material_ui/material_ui.dart';

/// هوية «المفضلة 2»: مكتبة خاصة بطابع سينمائي — أسود عميق، ذهبي شمباني يتدرج إلى وردي مخملي.
abstract final class C {
  static const bg = Color(0xFF0A0810);
  static const bg2 = Color(0xFF110E18);
  static const surface = Color(0xFF17131F);
  static const surface2 = Color(0xFF201A2B);
  static const line = Color(0x14FFFFFF);
  static const line2 = Color(0x26FFFFFF);
  static const text = Color(0xFFF5EFF7);
  static const muted = Color(0xFF9D94AB);
  static const gold = Color(0xFFE8B86D);
  static const gold2 = Color(0xFFF6DDA6);
  static const rose = Color(0xFFE2688C);
  static const plum = Color(0xFF34172F);
  static const ok = Color(0xFF5BC79A);
  static const danger = Color(0xFFE2566F);
  static const onAccent = Color(0xFF241307);
  static const grad = LinearGradient(colors: [gold2, gold, rose], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const scrim = LinearGradient(colors: [Color(0x00000000), Color(0xCC0A0810)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
}

/// مقاييس موحّدة (مسافات، حواف، مدد حركة).
abstract final class S {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;
  static const rSm = 12.0, rMd = 16.0, rLg = 22.0, rXl = 28.0;
  static const fast = Duration(milliseconds: 160), med = Duration(milliseconds: 260), slow = Duration(milliseconds: 420);
  static const ease = Cubic(.2, .8, .2, 1);
}

/// [font]: خط المستخدم المستورد (مثل «ثمانية») أو الافتراضي Plex — وPlex احتياطي لأي حرف ناقص.
ThemeData buildTheme({String font = 'Plex'}) {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: font, fontFamilyFallback: const ['Plex']);
  final cs = const ColorScheme.dark(
    primary: C.gold, onPrimary: C.onAccent, secondary: C.rose, onSecondary: Colors.white,
    surface: C.surface, onSurface: C.text, surfaceContainerHighest: C.surface2, outline: C.line2, error: C.danger,
  );
  final t = base.textTheme.apply(bodyColor: C.text, displayColor: C.text, fontFamily: font);
  return base.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    textTheme: t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.5),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: t.bodySmall?.copyWith(color: C.muted),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(color: C.surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.rLg), side: const BorderSide(color: C.line))),
    chipTheme: base.chipTheme.copyWith(backgroundColor: C.surface, selectedColor: C.gold.withValues(alpha: .18), side: const BorderSide(color: C.line2), labelStyle: TextStyle(fontFamily: font, color: C.text), shape: const StadiumBorder()),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.surface, hintStyle: const TextStyle(color: C.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(S.rMd), borderSide: const BorderSide(color: C.line2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(S.rMd), borderSide: const BorderSide(color: C.line2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(S.rMd), borderSide: const BorderSide(color: C.gold, width: 1.4)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: C.gold, foregroundColor: C.onAccent, minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.rMd)), textStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: C.text, minimumSize: const Size(48, 48), side: const BorderSide(color: C.line2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.rMd)))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.bg2.withValues(alpha: .92), indicatorColor: C.gold.withValues(alpha: .16), height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(fontFamily: font, fontSize: 11.5, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500, color: s.contains(WidgetState.selected) ? C.gold2 : C.muted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.gold2 : C.muted)),
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: C.bg2, indicatorColor: Color(0x2EE8B86D), selectedIconTheme: IconThemeData(color: C.gold2), unselectedIconTheme: IconThemeData(color: C.muted), selectedLabelTextStyle: TextStyle(fontFamily: font, color: C.gold2, fontWeight: FontWeight.w700), unselectedLabelTextStyle: TextStyle(fontFamily: font, color: C.muted)),
    snackBarTheme: SnackBarThemeData(backgroundColor: C.surface2, contentTextStyle: TextStyle(fontFamily: font, color: C.text), behavior: SnackBarBehavior.floating, showCloseIcon: true, closeIconColor: C.muted, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.rMd))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.bg2, showDragHandle: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(S.rXl)))),
    dialogTheme: DialogThemeData(backgroundColor: C.bg2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.rXl))),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
    focusColor: C.gold.withValues(alpha: .25),
    splashFactory: InkSparkle.splashFactory,
  );
}
