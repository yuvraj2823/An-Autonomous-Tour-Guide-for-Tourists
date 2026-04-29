import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor  = Color(0xFF1A6B4A);
  static const Color surfaceColor  = Color(0xFFF8F6F1);
  static const Color cardColor     = Color(0xFFFFFFFF);
  static const Color textPrimary   = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF6C6C70);
  static const Color accentColor   = Color(0xFFE8A838);

  static const String proximityLabel = '2.5m';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        surface: surfaceColor,
      ),
      scaffoldBackgroundColor: surfaceColor,
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        displayLarge: GoogleFonts.playfairDisplay(
            fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary),
        headlineMedium: GoogleFonts.playfairDisplay(
            fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge:  GoogleFonts.poppins(fontSize: 16, color: textPrimary),
        bodyMedium: GoogleFonts.poppins(fontSize: 14, color: textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: const CardThemeData(
        color: cardColor,
        elevation: 2,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceColor,
        labelStyle: GoogleFonts.poppins(fontSize: 12),
      ),
    );
  }
}
