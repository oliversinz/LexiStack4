import 'package:flutter/material.dart';

import '../app/controller.dart';

const kSans = 'LexiSans';
const kCondensed = 'LexiCondensed';

/// Game-specific colors not covered by [ColorScheme].
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.border,
    required this.tile,
    required this.tileInk,
    required this.tileEdge,
    required this.tileSelected,
    required this.tileSelectedInk,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.coin,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkSoft;
  final Color border;
  final Color tile;
  final Color tileInk;
  final Color tileEdge;
  final Color tileSelected;
  final Color tileSelectedInk;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color coin;

  static const light = Palette(
    bg: Color(0xFFF3EEE4),
    surface: Color(0xFFFFFCF6),
    surfaceAlt: Color(0xFFE9E1D3),
    ink: Color(0xFF1E1A2B),
    inkSoft: Color(0xFF5A5368),
    border: Color(0xFFD8CEBD),
    tile: Color(0xFFFFFDF8),
    tileInk: Color(0xFF1E1A2B),
    tileEdge: Color(0xFFCFC4B1),
    tileSelected: Color(0xFF2B2442),
    tileSelectedInk: Color(0xFFFFFFFF),
    primary: Color(0xFF2B2442),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFD9482B),
    coin: Color(0xFFC98A00),
  );

  static const dark = Palette(
    bg: Color(0xFF14121C),
    surface: Color(0xFF1F1C2A),
    surfaceAlt: Color(0xFF2A2638),
    ink: Color(0xFFF4F0FA),
    inkSoft: Color(0xFFB4ADC4),
    border: Color(0xFF3B3650),
    tile: Color(0xFF2C2840),
    tileInk: Color(0xFFF4F0FA),
    tileEdge: Color(0xFF0B0910),
    tileSelected: Color(0xFFF2C14E),
    tileSelectedInk: Color(0xFF1B1530),
    primary: Color(0xFFF2C14E),
    onPrimary: Color(0xFF1B1530),
    accent: Color(0xFFFF7A5C),
    coin: Color(0xFFF2C14E),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Tier reveal colors (amber, emerald, sapphire, amethyst). All use dark ink,
/// which keeps contrast above 7:1 in both light and dark themes.
const tierColors = [
  Color(0xFFF5C84C),
  Color(0xFF7DCB97),
  Color(0xFF8DB6F0),
  Color(0xFFC3A1EC),
];
const tierInk = Color(0xFF1B1530);
const tierNames = ['Straightforward', 'Moderate', 'Tricky', 'Lateral'];

Color tierColor(int tier) => tierColors[(tier - 1).clamp(0, 3)];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.light ? Palette.light : Palette.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF2B2442),
        brightness: brightness,
      ).copyWith(
        primary: p.primary,
        onPrimary: p.onPrimary,
        surface: p.surface,
        onSurface: p.ink,
        error: p.accent,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kSans,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kSans,
        fontWeight: FontWeight.w900,
        fontSize: 20,
        color: p.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        disabledBackgroundColor: p.surfaceAlt,
        disabledForegroundColor: p.inkSoft,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: kSans,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: kSans,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.primary,
      contentTextStyle: TextStyle(color: p.onPrimary, fontFamily: kSans),
    ),
    dividerTheme: DividerThemeData(color: p.border),
  );
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
  Duration motion(int ms) =>
      reduceMotion ? Duration.zero : Duration(milliseconds: ms);
}

/// Makes the controller available to every screen.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
