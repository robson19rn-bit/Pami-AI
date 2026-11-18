import 'package:material_ui/material_ui.dart';

import '../app_state.dart';

/// Spokojna, kontrastowa paleta (tekst ~15:1 na tle, przyciski ≥ 4.5:1).
class Palette {
  static const background = Color(0xFFFBF7EF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2933);
  static const primary = Color(0xFF235E50);
  static const onPrimary = Color(0xFFFFFFFF);
  static const soft = Color(0xFFE6EFEA);
  static const warn = Color(0xFF8A4B08);
  static const good = Color(0xFF1E6B3A);
  static const border = Color(0xFF52606D);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.primary,
    primary: Palette.primary,
    onPrimary: Palette.onPrimary,
    surface: Palette.surface,
    onSurface: Palette.ink,
  );
  return ThemeData(
    fontFamily: 'Roboto', // systemowa czcionka Androida z pełnymi polskimi znakami
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 20, color: Palette.ink),
      bodyMedium: TextStyle(fontSize: 18, color: Palette.ink),
      titleLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Palette.ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 20, fontWeight: FontWeight.w600),
        backgroundColor: Palette.primary,
        foregroundColor: Palette.onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: Palette.ink,
        side: const BorderSide(color: Palette.border, width: 1.5),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 18),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 18))),
    chipTheme: const ChipThemeData(labelStyle: TextStyle(fontFamily: 'Roboto', fontSize: 16, color: Palette.ink)),
    appBarTheme: const AppBarTheme(backgroundColor: Palette.background, foregroundColor: Palette.ink, elevation: 0),
  );
}

/// Dostęp do stanu aplikacji w drzewie widżetów.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
