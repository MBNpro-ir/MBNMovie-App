import 'package:flutter/material.dart';

abstract final class MovieColors {
  static const background = Color(0xFF080A0F);
  static const surface = Color(0xFF11141C);
  static const surfaceHigh = Color(0xFF1A1E29);
  static const orange = Color(0xFF557BFF);
  static const coral = Color(0xFF43C9CA);
  static const violet = Color(0xFF8D6BFF);
  static const cyan = Color(0xFF3FD8D4);
  static const text = Color(0xFFF7F7FA);
  static const muted = Color(0xFFA5A9B6);
}

abstract final class MovieTheme {
  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: MovieColors.background,
    sliderTheme: SliderThemeData(
      // Flutter 3.44 still defaults to the legacy M3 slider. Explicit opt-in
      // follows Flutter's updated-material-3-slider migration guide.
      // ignore: deprecated_member_use
      year2023: false,
      trackHeight: 10,
      trackGap: 6,
      thumbSize: const WidgetStatePropertyAll(Size(4, 36)),
      activeTrackColor: MovieColors.orange,
      secondaryActiveTrackColor: MovieColors.orange.withValues(alpha: .35),
      inactiveTrackColor: Colors.white12,
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // Android 14+ drives this transition directly from the edge-swipe
        // progress. Releasing completes it; canceling smoothly restores the
        // current page. Older Android versions use Flutter's fade fallback.
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(
          fallbackColor: MovieColors.background,
        ),
        TargetPlatform.windows: _MbnmoviePageTransitionsBuilder(),
        TargetPlatform.linux: _MbnmoviePageTransitionsBuilder(),
        TargetPlatform.macOS: _MbnmoviePageTransitionsBuilder(),
      },
    ),
    colorScheme: const ColorScheme.dark(
      primary: MovieColors.orange,
      onPrimary: Color(0xFF241000),
      secondary: MovieColors.violet,
      tertiary: MovieColors.cyan,
      surface: MovieColors.surface,
      onSurface: MovieColors.text,
      surfaceContainer: MovieColors.surface,
      surfaceContainerHigh: MovieColors.surfaceHigh,
      outline: Color(0xFF353A49),
      error: MovieColors.coral,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.4,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.7),
      bodyMedium: TextStyle(fontSize: 13, height: 1.65),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MovieColors.surfaceHigh.withValues(alpha: .88),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Color(0xFF292E3B)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: MovieColors.orange, width: 1.4),
      ),
      hintStyle: const TextStyle(color: MovieColors.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: MovieColors.surface.withValues(alpha: .96),
      indicatorColor: MovieColors.orange.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? MovieColors.orange
              : MovieColors.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        animationDuration: const Duration(milliseconds: 180),
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        animationDuration: const Duration(milliseconds: 160),
        overlayColor: WidgetStateProperty.all(
          MovieColors.orange.withValues(alpha: .14),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: MovieColors.surfaceHigh,
      selectedColor: MovieColors.orange.withValues(alpha: .2),
      side: const BorderSide(color: Color(0xFF2A2F3C)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: const TextStyle(fontFamily: 'Vazirmatn'),
    ),
  );
}

class _MbnmoviePageTransitionsBuilder extends PageTransitionsBuilder {
  const _MbnmoviePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
