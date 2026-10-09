import 'package:flutter/material.dart';

/// Minimal monochrome theme: neutral surfaces, hairline borders, no elevation.
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF18181B),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      ).copyWith(
        primary: dark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
        onPrimary: dark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF),
        primaryContainer: dark
            ? const Color(0xFF27272A)
            : const Color(0xFFF4F4F5),
        onPrimaryContainer: dark
            ? const Color(0xFFF4F4F5)
            : const Color(0xFF18181B),
        secondaryContainer: dark
            ? const Color(0xFF27272A)
            : const Color(0xFFF4F4F5),
        onSecondaryContainer: dark
            ? const Color(0xFFF4F4F5)
            : const Color(0xFF18181B),
        surface: dark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF),
        onSurface: dark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
        onSurfaceVariant: dark
            ? const Color(0xFFA1A1AA)
            : const Color(0xFF71717A),
        surfaceContainerLowest: dark
            ? const Color(0xFF0B0B0C)
            : const Color(0xFFFFFFFF),
        surfaceContainerLow: dark
            ? const Color(0xFF151517)
            : const Color(0xFFFAFAFA),
        surfaceContainer: dark
            ? const Color(0xFF1A1A1D)
            : const Color(0xFFF4F4F5),
        surfaceContainerHigh: dark
            ? const Color(0xFF222225)
            : const Color(0xFFEFEFF1),
        surfaceContainerHighest: dark
            ? const Color(0xFF27272A)
            : const Color(0xFFE4E4E7),
        outline: dark ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
        outlineVariant: dark
            ? const Color(0xFF27272A)
            : const Color(0xFFE4E4E7),
        surfaceTint: Colors.transparent,
      );

  const radius = BorderRadius.all(Radius.circular(10));
  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: color),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: inputBorder(colors.outlineVariant),
      enabledBorder: inputBorder(colors.outlineVariant),
      focusedBorder: inputBorder(colors.onSurface),
      errorBorder: inputBorder(colors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurface,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      iconColor: colors.onSurfaceVariant,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      iconColor: colors.onSurfaceVariant,
      collapsedIconColor: colors.onSurfaceVariant,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: colors.onSurface),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: colors.onSurface,
      contentTextStyle: TextStyle(color: colors.surface),
      shape: const RoundedRectangleBorder(borderRadius: radius),
    ),
  );
}
