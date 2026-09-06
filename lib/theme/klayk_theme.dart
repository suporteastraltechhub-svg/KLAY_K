import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// ============================================================================
/// KLAY K — Design Tokens Premium
/// Identidade: preto profundo, roxo premium, neon equilibrado, futurista.
/// ============================================================================

class KlaykColors extends ThemeExtension<KlaykColors> {
  // -- fundos ---------------------------------------------------------------
  final Color bg; // preto profundo base
  final Color bgElevated; // superfícies elevadas
  final Color surface; // cards
  final Color surfaceAlt;
  final Color border;
  // -- roxo premium ---------------------------------------------------------
  final Color primary;
  final Color primarySoft;
  final Color primaryFaint;
  final Color accent;
  final Color glow;
  // -- semântica ------------------------------------------------------------
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color gold;
  final Color like;

  const KlaykColors({
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.primary,
    required this.primarySoft,
    required this.primaryFaint,
    required this.accent,
    required this.glow,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.gold,
    required this.like,
  });

  static const KlaykColors dark = KlaykColors(
    bg: Color(0xFF08070D),
    bgElevated: Color(0xFF0E0C16),
    surface: Color(0xFF17141F),
    surfaceAlt: Color(0xFF1E1A2B),
    border: Color(0xFF2A2540),
    primary: Color(0xFF8B5CF6),
    primarySoft: Color(0xFFB794FF),
    primaryFaint: Color(0xFF6D28D9),
    accent: Color(0xFFC084F0),
    glow: Color(0xFF8B5CF6),
    success: Color(0xFF34D399),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFE4183C),
    info: Color(0xFF38BDF8),
    gold: Color(0xFFD4AF37),
    like: Color(0xFFFF4D6A),
  );

  /// Gradiente premium base (roxo profundo → preto).
  static const LinearGradient baseGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF171127), Color(0xFF0B0913), Color(0xFF08070D)],
  );

  /// Gradiente "purple glow" para destaques (logo/badges).
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  );

  /// Gradiente metalizado (neo-purple → violeta claro).
  static const LinearGradient glowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB794FF), Color(0xFF6D28D9)],
  );

  @override
  KlaykColors copyWith({
    Color? bg,
    Color? bgElevated,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? primary,
    Color? primarySoft,
    Color? primaryFaint,
    Color? accent,
    Color? glow,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? gold,
    Color? like,
  }) {
    return KlaykColors(
      bg: bg ?? this.bg,
      bgElevated: bgElevated ?? this.bgElevated,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryFaint: primaryFaint ?? this.primaryFaint,
      accent: accent ?? this.accent,
      glow: glow ?? this.glow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      gold: gold ?? this.gold,
      like: like ?? this.like,
    );
  }

  @override
  KlaykColors lerp(KlaykColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return KlaykColors(
      bg: c(bg, other.bg),
      bgElevated: c(bgElevated, other.bgElevated),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      primary: c(primary, other.primary),
      primarySoft: c(primarySoft, other.primarySoft),
      primaryFaint: c(primaryFaint, other.primaryFaint),
      accent: c(accent, other.accent),
      glow: c(glow, other.glow),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      info: c(info, other.info),
      gold: c(gold, other.gold),
      like: c(like, other.like),
    );
  }
}

/// Acessor rápido: cores do tema KLAY K.
KlaykColors kcolors(BuildContext context) =>
    Theme.of(context).extension<KlaykColors>() ?? KlaykColors.dark;

/// Construção do ThemeData premium do KLAY K.
class KlaykTheme {
  KlaykTheme._();

  /// `reduceMotion` desliga transições longas (acessibilidade / economia).
  static ThemeData dark({bool reduceMotion = false}) {
    const palette = KlaykColors.dark;
    // Em `flutter test` o asset do shader Sparkle não existe no bundle de
    // teste → usa `InkRipple` (determinístico, mesmo padrão de `_inTests` que
    // o resto do app já usa). Em produção mantém o efeito Sparkle.
    final inTests = Platform.environment['FLUTTER_TEST'] == 'true';
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: Brightness.dark,
      surface: palette.bg,
    ).copyWith(
      primary: palette.primary,
      secondary: palette.primarySoft,
      tertiary: palette.accent,
      error: palette.danger,
      onPrimary: Colors.white,
      onSurface: Colors.white,
      surface: palette.bg,
      surfaceContainer: palette.surface,
      surfaceContainerLow: palette.bgElevated,
      surfaceContainerHigh: palette.surfaceAlt,
      outline: palette.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bg,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          )
          .copyWith(
            bodySmall: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
      extensions: const [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: Colors.white,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 0.5),
      iconTheme: const IconThemeData(color: Colors.white),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF17141F),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(palette.primary),
        trackColor: const WidgetStatePropertyAll(Color(0xFF2A2340)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: reduceMotion
                ? const FadeUpwardsPageTransitionsBuilder()
                : const _KlaykPageTransitionsBuilder(),
        },
      ),
      splashFactory: reduceMotion || inTests
          ? InkRipple.splashFactory
          : InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}

/// Transição de página premium: leve escala + fade + slide vertical discreto.
class _KlaykPageTransitionsBuilder extends PageTransitionsBuilder {
  const _KlaykPageTransitionsBuilder();

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
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}