import 'package:flutter/material.dart';

/// ENTROPY's terminal palette: the same colours as the notebook's charts.
/// Every text colour has at least 4.5:1 contrast on [surface].
abstract final class Palette {
  static const surface = Color(0xFF0B0F0C); // terminal black
  static const panel = Color(0xFF111713); // raised panels
  static const ink = Color(0xFFD7E0D9); // main text
  static const muted = Color(0xFF8A968D); // secondary text
  static const outline = Color(0xFF566A5C); // field borders, 3:1 on surface
  static const grid = Color(0xFF1C241F); // dividers
  static const green = Color(0xFF22B05F); // prompt, action, result
  static const blue = Color(0xFF3B9BE0); // model information
  static const amber = Color(0xFFC27E00); // money figures
  static const rose = Color(0xFFDC4C7C); // errors
}

const _fontFamily = 'JetBrainsMono';

ThemeData entropyTheme() {
  const scheme = ColorScheme.dark(
    surface: Palette.surface,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.muted,
    surfaceContainer: Palette.panel,
    primary: Palette.green,
    onPrimary: Palette.surface,
    secondary: Palette.blue,
    onSecondary: Palette.surface,
    tertiary: Palette.amber,
    onTertiary: Palette.surface,
    error: Palette.rose,
    onError: Palette.surface,
    outline: Palette.outline,
    outlineVariant: Palette.grid,
  );
  const fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
    borderSide: BorderSide(color: Palette.outline),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: _fontFamily,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(borderSide: const BorderSide(color: Palette.green, width: 1.5)),
      labelStyle: const TextStyle(color: Palette.muted),
      floatingLabelStyle: const TextStyle(color: Palette.green),
      hintStyle: const TextStyle(color: Palette.muted),
      helperStyle: const TextStyle(color: Palette.muted),
      helperMaxLines: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(52),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
        textStyle: const TextStyle(fontFamily: _fontFamily, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Palette.green),
  );
}
