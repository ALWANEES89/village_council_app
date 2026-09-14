import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFFD84315);
  static const primaryDark = Color(0xFFBF360C);
  static const secondary = Color(0xFFFFB300);
  static const background = Color(0xFFFFF8F1);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF5F7FA);
  static const textDark = Color(0xFF2D241E);
  static const textSecondary = Color(0xFF667085);
  static const success = Color(0xFF0A8F63);
  static const warning = Color(0xFFE06B17);
  static const error = Color(0xFFC62828);
  static const border = Color(0xFFE6EAF0);

  static const primaryGradient = LinearGradient(
    colors: [Color(0xFFD84315), Color(0xFFFF8A65)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static final primaryShadow = BoxShadow(
    color: primary.withValues(alpha: 0.35),
    blurRadius: 20,
    offset: const Offset(0, 8),
  );
}

class AppSpacing {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppRadius {
  static const card = 22.0;
  static const tile = 16.0;
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
        ),
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: Colors.black12,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        useMaterial3: true,
      );
}
