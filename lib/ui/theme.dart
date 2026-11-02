import 'package:flutter/material.dart';

const forest = Color(0xff174c41);
const lime = Color(0xffd6ed9f);
const canvas = Color(0xfff5f6ef);

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: forest,
        brightness: brightness,
        primary: dark ? lime : forest,
        surface: dark ? const Color(0xff222226) : const Color(0xfff4f7f2),
      ).copyWith(
        onSurface: dark ? Colors.white : const Color(0xff1d1d1f),
        onSurfaceVariant: dark
            ? const Color(0xffa5a5af)
            : const Color(0xff575a60),
        outlineVariant: dark
            ? const Color(0xff3b3b40)
            : const Color(0xffcbd5ce),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    brightness: brightness,
    fontFamily: 'Inter',
  );
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 34,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? Colors.white.withValues(alpha: .065)
          : Colors.white.withValues(alpha: .65),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.outlineVariant, width: .5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        minimumSize: const Size(0, 52),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: dark ? forest : lime,
      height: 76,
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: .5),
      space: 32,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      showDragHandle: false,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xf02c2c30) : const Color(0xf5f5f7f4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: ListTileThemeData(
      textColor: colors.onSurface,
      iconColor: colors.primary,
      minVerticalPadding: 10,
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(fontSize: 16),
      subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        color: colors.onSurfaceVariant,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xff38383d) : forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
