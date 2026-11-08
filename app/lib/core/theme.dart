import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const brandBlue = Color(0xFF0B2545);
const brandYellow = Color(0xFFFFC400);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Color(0xFF8DB4F0), onPrimary: Color(0xFF0B2545), secondary: Color(0xFFB8C2D0),
          surface: Color(0xFF17202C), onSurface: Color(0xFFE8EDF4), error: Color(0xFFFF8A80),
          surfaceContainerHighest: Color(0xFF223044), outline: Color(0xFF3A4A60),
          secondaryContainer: Color(0xFF2D4A73), onSecondaryContainer: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFF2D4A73), onPrimaryContainer: Color(0xFFFFFFFF))
      : const ColorScheme.light(
          primary: brandBlue, onPrimary: Colors.white, secondary: Color(0xFF2B2F36),
          surface: Colors.white, onSurface: Color(0xFF1B2330), error: Color(0xFFB3261E),
          surfaceContainerHighest: Color(0xFFE9EEF5), outline: Color(0xFFD5DCE6),
          secondaryContainer: Color(0xFFDCE6F5), onSecondaryContainer: Color(0xFF0B2545),
          primaryContainer: Color(0xFFDCE6F5), onPrimaryContainer: Color(0xFF0B2545));
  final base = ThemeData(brightness: b, useMaterial3: true);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0E141C) : const Color(0xFFF4F6F9),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
      foregroundColor: scheme.onSurface,
      titleTextStyle: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface, indicatorShape: const StadiumBorder(),
      indicatorColor: scheme.primary.withOpacity(.16), height: 68,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.primary : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
  );
}
