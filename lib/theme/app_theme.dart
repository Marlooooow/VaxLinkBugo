import 'package:flutter/material.dart';

class AppTheme {
  // Core brand palette: calm clinical navy and muted blue.
  static const primaryBlue = Color(0xFF4F7FD8);
  static const secondaryBlue = Color(0xFF6B82AD);
  static const lightBackground = Color(0xFFF4F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaisedSurface = Color(0xFFF8FAFD);
  static const ink = Color(0xFF1E293B);
  static const mutedInk = Color(0xFF64748B);
  static const softBlue = Color(0xFFE8F0FD);
  static const outline = Color(0xFFD8E0EC);

  static const darkBackground = Color(0xFF10141B);
  static const darkSurface = Color(0xFF191F29);
  static const darkRaisedSurface = Color(0xFF222A36);
  static const darkText = Color(0xFFF2F4F7);
  static const darkMutedText = Color(0xFFAAB3C2);
  static const darkOutline = Color(0xFF303947);
  static const darkHighlight = Color(0xFF79A6F6);

  // Compatibility aliases retained for existing screens while the visual
  // language moves away from teal.
  static const primaryTeal = primaryBlue;
  static const healthcareGreen = secondaryBlue;
  static const background = lightBackground;
  static const softTeal = softBlue;

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  /// The login screen uses the same palette as the rest of the application.
  static ThemeData get loginTheme => lightTheme;

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final backgroundColor = isDark ? darkBackground : lightBackground;
    final surfaceColor = isDark ? darkSurface : lightSurface;
    final raisedSurface = isDark ? darkRaisedSurface : lightRaisedSurface;
    final foreground = isDark ? darkText : ink;
    final mutedForeground = isDark ? darkMutedText : mutedInk;
    final borderColor = isDark ? darkOutline : outline;
    final primary = isDark ? darkHighlight : primaryBlue;
    final primaryContainer = isDark ? const Color(0xFF263A5B) : softBlue;
    final onPrimaryContainer = isDark
        ? const Color(0xFFDCE8FF)
        : const Color(0xFF284D8E);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: isDark ? const Color(0xFF0C1C35) : Colors.white,
          secondary: isDark ? const Color(0xFFAFC5ED) : secondaryBlue,
          onSecondary: isDark ? const Color(0xFF17243B) : Colors.white,
          surface: surfaceColor,
          onSurface: foreground,
          onSurfaceVariant: mutedForeground,
          primaryContainer: primaryContainer,
          onPrimaryContainer: onPrimaryContainer,
          outline: isDark ? const Color(0xFF788596) : const Color(0xFF7A8799),
          outlineVariant: borderColor,
          surfaceContainerLowest: isDark
              ? const Color(0xFF0C1016)
              : Colors.white,
          surfaceContainerLow: surfaceColor,
          surfaceContainer: raisedSurface,
          surfaceContainerHigh: isDark
              ? const Color(0xFF28313E)
              : const Color(0xFFEEF2F8),
          surfaceContainerHighest: isDark
              ? const Color(0xFF303A48)
              : const Color(0xFFE7ECF4),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: backgroundColor,
    );
    final roundedButton = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      iconTheme: IconThemeData(color: foreground),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: backgroundColor,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: foreground,
          fontSize: 20,
          height: 1.15,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: borderColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raisedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raisedSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: raisedSurface,
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(color: borderColor, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : mutedForeground,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : mutedForeground,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceColor,
        selectedColor: primaryContainer,
        disabledColor: raisedSurface,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(
          color: onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        labelStyle: TextStyle(color: mutedForeground),
        hintStyle: TextStyle(color: mutedForeground),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: borderColor.withValues(alpha: 0.65)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 54),
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: mutedForeground,
          shape: roundedButton,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: mutedForeground,
          shape: roundedButton,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          foregroundColor: primary,
          side: BorderSide(color: borderColor),
          shape: roundedButton,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF2A3442)
            : const Color(0xFF263448),
        contentTextStyle: const TextStyle(color: Color(0xFFF8FAFC)),
        actionTextColor: const Color(0xFF9DBEFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raisedSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
