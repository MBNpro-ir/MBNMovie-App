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
  static ThemeData get dark => buildTheme();

  static ThemeData buildTheme({
    bool highContrast = false,
    VisualDensity visualDensity = VisualDensity.standard,
    bool reduceMotion = false,
    bool boldText = false,
    Color? focusColor,
    Color? hoverColor,
  }) {
    final baseBg = highContrast ? Colors.black : MovieColors.background;
    final baseSurface = highContrast
        ? const Color(0xFF0C0E14)
        : MovieColors.surface;
    final baseSurfaceHigh = highContrast
        ? const Color(0xFF171B24)
        : MovieColors.surfaceHigh;
    final primaryColor = highContrast
        ? const Color(0xFF6B8EFF)
        : MovieColors.orange;
    final outlineColor = highContrast
        ? Colors.white70
        : const Color(0xFF353A49);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: baseBg,
      visualDensity: visualDensity,
      focusColor: focusColor,
      hoverColor: hoverColor,
      cardTheme: CardThemeData(
        color: baseSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: baseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: highContrast ? Colors.white60 : Colors.white12,
        thickness: highContrast ? 1.5 : 1.0,
      ),
      sliderTheme: SliderThemeData(
        // Flutter 3.44 still defaults to the legacy M3 slider. Explicit opt-in
        // follows Flutter's updated-material-3-slider migration guide.
        // ignore: deprecated_member_use
        year2023: false,
        trackHeight: 10,
        trackGap: 6,
        thumbSize: const WidgetStatePropertyAll(Size(4, 36)),
        activeTrackColor: primaryColor,
        secondaryActiveTrackColor: primaryColor.withValues(alpha: .35),
        inactiveTrackColor: highContrast ? Colors.white30 : Colors.white12,
        showValueIndicator: ShowValueIndicator.always,
      ),
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                TargetPlatform.windows: _MbnmoviePageTransitionsBuilder(),
                TargetPlatform.linux: _MbnmoviePageTransitionsBuilder(),
                TargetPlatform.macOS: _MbnmoviePageTransitionsBuilder(),
              },
            ),
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        onPrimary: const Color(0xFF241000),
        secondary: MovieColors.violet,
        tertiary: MovieColors.cyan,
        surface: baseSurface,
        onSurface: highContrast ? Colors.white : MovieColors.text,
        surfaceContainer: baseSurface,
        surfaceContainerHigh: baseSurfaceHigh,
        outline: outlineColor,
        error: MovieColors.coral,
      ),
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 32,
          height: 1.25,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.4,
          fontWeight: boldText ? FontWeight.w800 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: boldText ? FontWeight.w800 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.7,
          fontWeight: boldText ? FontWeight.w600 : FontWeight.normal,
          color: highContrast ? Colors.white : null,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          height: 1.65,
          fontWeight: boldText ? FontWeight.w600 : FontWeight.normal,
          color: highContrast ? Colors.white.withValues(alpha: 0.92) : null,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          color: highContrast ? Colors.white : null,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: baseSurfaceHigh.withValues(alpha: .88),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.5)
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: highContrast ? Colors.white70 : const Color(0xFF292E3B),
            width: highContrast ? 1.5 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(
            color: primaryColor,
            width: highContrast ? 2.0 : 1.4,
          ),
        ),
        hintStyle: TextStyle(
          color: highContrast ? Colors.white60 : MovieColors.muted,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: baseSurface.withValues(alpha: .96),
        indicatorColor: primaryColor.withValues(alpha: .18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : (highContrast ? Colors.white70 : MovieColors.muted),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          animationDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: highContrast
              ? const BorderSide(color: Colors.white70, width: 1.2)
              : BorderSide.none,
          textStyle: TextStyle(
            fontFamily: 'Vazirmatn',
            fontWeight: boldText ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          overlayColor: WidgetStateProperty.all(
            primaryColor.withValues(alpha: .14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: baseSurfaceHigh,
        selectedColor: primaryColor.withValues(alpha: .2),
        side: BorderSide(
          color: highContrast ? Colors.white70 : const Color(0xFF2A2F3C),
          width: highContrast ? 1.5 : 1.0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: boldText ? FontWeight.w700 : FontWeight.normal,
          color: MovieColors.text,
        ),
        secondaryLabelStyle: const TextStyle(color: MovieColors.text),
        checkmarkColor: MovieColors.text,
      ),
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
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
