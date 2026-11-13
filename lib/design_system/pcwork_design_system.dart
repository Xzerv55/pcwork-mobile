import 'package:flutter/material.dart';

/// PCWork 2030 visual foundations. Shared tokens and reusable surfaces live
/// here so screens can be migrated incrementally without changing behaviour.
abstract final class PCWorkColors {
  static const Color midnight = Color(0xFF050B18);
  static const Color deepNavy = Color(0xFF0B1530);
  static const Color navy = Color(0xFF101D38);
  static const Color glass = Color(0xB3162948);
  static const Color glassStrong = Color(0xE6101D35);
  static const Color electricBlue = Color(0xFF168BFF);
  static const Color cyan = Color(0xFF21D4D8);
  static const Color violet = Color(0xFF8057FF);
  static const Color success = Color(0xFF20E39A);
  static const Color warning = Color(0xFFFFC857);
  static const Color danger = Color(0xFFFF647C);
  static const Color textPrimary = Color(0xFFF4F8FF);
  static const Color textSecondary = Color(0xFFAFBED4);
  static const Color textMuted = Color(0xFF8193AE);
  static const Color lightBackground = Color(0xFFF3F6FB);
  static const Color lightText = Color(0xFF172033);
}

abstract final class PCWorkSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double section = 40;
}

abstract final class PCWorkRadii {
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 30;
  static const double pill = 999;
}

abstract final class PCWorkEffects {
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PCWorkColors.midnight, PCWorkColors.deepNavy, Color(0xFF090F22)],
  );

  static const LinearGradient glass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xCC1C3458), Color(0x99101D35)],
  );

  static const LinearGradient primaryAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PCWorkColors.electricBlue, PCWorkColors.cyan],
  );

  static List<BoxShadow> get softGlassShadow => [
        BoxShadow(
          color: PCWorkColors.electricBlue.withValues(alpha: .10),
          blurRadius: 28,
          spreadRadius: -8,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: .24),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

/// Reusable translucent panel for the incremental screen redesign.
class PCWorkGlassPanel extends StatelessWidget {
  const PCWorkGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PCWorkSpacing.lg),
    this.radius = PCWorkRadii.lg,
    this.gradient,
    this.borderColor,
    this.glow = false,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Gradient? gradient;
  final Color? borderColor;
  final bool glow;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: gradient ?? (dark ? PCWorkEffects.glass : null),
        color: dark ? null : Colors.white,
        border: Border.all(
          color: borderColor ?? (dark
              ? PCWorkColors.electricBlue.withValues(alpha: .22)
              : const Color(0xFFE2E9F2)),
        ),
        boxShadow: glow && dark
            ? PCWorkEffects.softGlassShadow
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .12 : .05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// Compact glowing icon container for future quick-action cards.
class PCWorkGlowIcon extends StatelessWidget {
  const PCWorkGlowIcon({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.color = PCWorkColors.electricBlue,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: .30), color.withValues(alpha: .08)],
        ),
        border: Border.all(color: color.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .20), blurRadius: 18, spreadRadius: -4),
        ],
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Shared theme factory. Keeps a usable light theme while defining the 2030
/// dark-glass direction as the primary visual language.
abstract final class PCWorkTheme {
  static ThemeData build({required bool dark}) {
    const accent = PCWorkColors.cyan;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final foreground = dark ? PCWorkColors.textPrimary : PCWorkColors.lightText;
    final muted = dark ? PCWorkColors.textSecondary : const Color(0xFF34445A);
    final outline = dark ? const Color(0xFF294365) : const Color(0xFFC8D4E2);
    final surface = dark ? const Color(0xFF101D32) : const Color(0xFFFFFFFF);
    const lightCanvas = Color(0xFFF0F4F9);
    const lightSurfaceAlt = Color(0xFFF7F9FC);
    const lightPrimary = Color(0xFF087F83);

    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      }),
      brightness: brightness,
      fontFamily: 'NotoSans',
      scaffoldBackgroundColor: dark ? PCWorkColors.midnight : lightCanvas,
      canvasColor: dark ? PCWorkColors.midnight : lightCanvas,
      cardColor: surface,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
        primary: dark ? PCWorkColors.electricBlue : lightPrimary,
        secondary: PCWorkColors.violet,
        tertiary: dark ? PCWorkColors.cyan : const Color(0xFF6B55C7),
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        surfaceContainerHighest: dark ? const Color(0xFF1A2A42) : const Color(0xFFE8EEF5),
        onSurface: foreground,
        outline: outline,
      ),
      splashFactory: InkSparkle.splashFactory,
      splashColor: accent.withValues(alpha: .18),
      highlightColor: accent.withValues(alpha: .10),
      hoverColor: accent.withValues(alpha: .06),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 62,
        iconTheme: IconThemeData(color: muted, size: 22),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
        headlineLarge: TextStyle(fontSize: 29, height: 1.12, fontWeight: FontWeight.w800, letterSpacing: -.8, color: foreground),
        headlineMedium: TextStyle(fontSize: 24, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -.55, color: foreground),
        titleLarge: TextStyle(fontSize: 19, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -.25, color: foreground),
        titleMedium: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w700, color: foreground),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: muted),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: dark ? PCWorkColors.textMuted : const Color(0xFF596B80)),
        titleSmall: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w700, color: foreground),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: foreground),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: dark ? 0 : 2,
        shadowColor: Colors.black.withValues(alpha: dark ? .14 : .06),
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), side: BorderSide(color: outline)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF0D192B) : lightSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: dark ? PCWorkColors.textMuted : const Color(0xFF66778D), fontSize: 13),
        labelStyle: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), borderSide: BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), borderSide: BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), borderSide: const BorderSide(color: accent, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), borderSide: const BorderSide(color: PCWorkColors.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PCWorkRadii.md), borderSide: const BorderSide(color: PCWorkColors.danger, width: 1.6)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xFF111F35) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PCWorkRadii.xl), side: BorderSide(color: outline)),
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: foreground),
        contentTextStyle: TextStyle(fontSize: 14, height: 1.4, color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF101D32) : Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: dark ? const Color(0xFF60758D) : const Color(0xFFB5C2D1),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF1B2B45) : const Color(0xFF17283D),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: dark ? accent : lightPrimary,
        selectionColor: (dark ? accent : lightPrimary).withValues(alpha: .22),
        selectionHandleColor: dark ? accent : lightPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : (dark ? const Color(0xFF8FA2BB) : const Color(0xFF718096))),
        trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? (dark ? accent : lightPrimary) : outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? (dark ? accent : lightPrimary) : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: muted, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? (dark ? accent : lightPrimary) : muted)),
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xFF14243B) : Colors.white,
        textStyle: TextStyle(color: foreground, fontSize: 14),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: outline)),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: foreground, fontSize: 14),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: dark ? const Color(0xFF0D192B) : lightSurfaceAlt),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 22),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: foreground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
        minLeadingWidth: 34,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF172943) : const Color(0xFFEAF1F7),
        selectedColor: accent.withValues(alpha: .18),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: dark ? const Color(0xFFD7E3EF) : const Color(0xFF34465D), fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: dark ? accent : const Color(0xFF087F83), linearTrackColor: outline),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF0B1425) : Colors.white,
        indicatorColor: accent.withValues(alpha: .16),
        elevation: 0,
        height: 76,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? (dark ? accent : const Color(0xFF087F83)) : (dark ? PCWorkColors.textMuted : const Color(0xFF596B80)),
        )),
      ),
      filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.disabled) ? (dark ? accent.withValues(alpha: .35) : const Color(0xFF087F83).withValues(alpha: .45)) : (dark ? accent : const Color(0xFF087F83))),
        foregroundColor: WidgetStatePropertyAll(dark ? const Color(0xFF061319) : Colors.white),
        overlayColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.pressed) ? const Color(0xFF061319).withValues(alpha: .24) : Colors.transparent),
        shadowColor: WidgetStatePropertyAll(accent.withValues(alpha: .30)),
        elevation: const WidgetStatePropertyAll(2),
        animationDuration: const Duration(milliseconds: 150),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
      )),
    );
  }
}
