import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Design tokens of the "页边" design (design-demos/final.html).
@immutable
class MnotePalette extends ThemeExtension<MnotePalette> {
  const new({
    required this.dark,
    this.paperTint = false,
    required this.board,
    required this.paper,
    required this.paper2,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.accent,
    required this.gap,
  });

  final bool dark;

  /// 护眼纸色: warm paper surfaces and PDF pages tinted to paper.
  final bool paperTint;

  /// Window background behind pages.
  final Color board;

  /// PDF page / main surfaces.
  final Color paper;
  final Color paper2;
  final Color card;
  final Color ink, ink2, ink3;
  final Color line;

  /// Vermilion accent: current tool, primary actions.
  final Color accent;

  /// Gap between PDF pages.
  final Color gap;

  static const light = MnotePalette(
    dark: false,
    board: Color(0xFFECE6D9),
    paper: Color(0xFFF7F3EA),
    paper2: Color(0xFFFBF8F2),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF2A251E),
    ink2: Color(0xFF5E574B),
    ink3: Color(0xFF665F53),
    line: Color(0xFFE3DBCB),
    accent: Color(0xFFB4532A),
    gap: Color(0xFFEAE3D4),
  );

  /// 护眼纸色: warm, slightly lower-contrast paper; text stays dark enough
  /// for ≥4.5:1 on every surface.
  static const paperTheme = MnotePalette(
    dark: false,
    paperTint: true,
    board: Color(0xFFE6DABF),
    paper: Color(0xFFF2E6C9),
    paper2: Color(0xFFF5EBD2),
    card: Color(0xFFFAF1DB),
    ink: Color(0xFF3A3024),
    ink2: Color(0xFF5A4E3C),
    ink3: Color(0xFF64573F),
    line: Color(0xFFD9CBA8),
    accent: Color(0xFFA54A22),
    gap: Color(0xFFE2D5B6),
  );

  static const night = MnotePalette(
    dark: true,
    board: Color(0xFF141210),
    paper: Color(0xFF1D1A16),
    paper2: Color(0xFF24201B),
    card: Color(0xFF2B2620),
    ink: Color(0xFFECE5D8),
    ink2: Color(0xFFCFC5B3),
    ink3: Color(0xFFACA290),
    line: Color(0xFF3B352D),
    accent: Color(0xFFE07A4E),
    gap: Color(0xFF141210),
  );

  static MnotePalette of(BuildContext context) =>
      Theme.of(context).extension<MnotePalette>() ?? light;

  @override
  MnotePalette copyWith() => this;

  @override
  MnotePalette lerp(ThemeExtension<MnotePalette>? other, double t) =>
      (other is MnotePalette && t >= 0.5) ? other : this;
}

/// Serif stack for reading text and titles (Noto Serif CJK ships with most
/// Android builds as the system "serif" CJK fallback).
const mnoteSerif = <String>['Noto Serif CJK SC', 'Noto Serif SC', 'serif'];

/// Builds the mNote theme on top of the app theme so Saber screens keep
/// working while mNote screens get the paper look.
ThemeData mnoteTheme(
  ThemeData base, {
  required bool night,
  bool paper = false,
}) {
  final p = night
      ? MnotePalette.night
      : (paper ? MnotePalette.paperTheme : MnotePalette.light);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: night ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: p.accent,
        onPrimary: Colors.white,
        surface: p.paper,
        onSurface: p.ink,
        onSurfaceVariant: p.ink2,
        outline: p.line,
        outlineVariant: p.line,
      );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: p.board,
    canvasColor: p.paper,
    dividerColor: p.line,
    extensions: [...base.extensions.values.where((e) => e is! MnotePalette), p],
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

/// The three reading themes (top-bar theme button).
enum ReadingTheme {
  day('日间'),
  paper('护眼纸色'),
  night('夜读');

  new(this.label);
  final String label;
}

/// Global reading theme for mNote screens.
final mnoteReadingTheme = ValueNotifier<ReadingTheme>(ReadingTheme.day);

/// Night mode on/off (kept for callers that only care about night).
final mnoteNight = _NightSwitch();

class _NightSwitch implements ValueListenable<bool> {
  @override
  bool get value => mnoteReadingTheme.value == ReadingTheme.night;
  set value(bool v) =>
      mnoteReadingTheme.value = v ? ReadingTheme.night : ReadingTheme.day;
  @override
  void addListener(VoidCallback l) => mnoteReadingTheme.addListener(l);
  @override
  void removeListener(VoidCallback l) => mnoteReadingTheme.removeListener(l);
}

/// PDF page tint per theme: night inverts to warm light-on-dark; paper
/// multiplies pages toward the paper colour (text stays near black).
ColorFilter? pageFilterFor(MnotePalette p) => p.dark
    ? const ColorFilter.matrix([
        -0.86, 0, 0, 0, 236, //
        0, -0.86, 0, 0, 229,
        0, 0, -0.86, 0, 216,
        0, 0, 0, 1, 0,
      ])
    : p.paperTint
    ? const ColorFilter.matrix([
        0.93, 0, 0, 0, 8, //
        0, 0.88, 0, 0, 8,
        0, 0, 0.74, 0, 8,
        0, 0, 0, 1, 0,
      ])
    : null;

/// Wraps [child] in the mNote theme and rebuilds on theme changes.
class MnoteThemed extends StatelessWidget {
  const new({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadingTheme>(
      valueListenable: mnoteReadingTheme,
      builder: (context, t, _) => Theme(
        data: mnoteTheme(
          Theme.of(context),
          night: t == ReadingTheme.night,
          paper: t == ReadingTheme.paper,
        ),
        child: child,
      ),
    );
  }
}

TextStyle serifStyle(
  Color color, {
  double size = 15,
  FontWeight weight = FontWeight.w400,
  double? height,
}) => TextStyle(
  fontFamilyFallback: mnoteSerif,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);
