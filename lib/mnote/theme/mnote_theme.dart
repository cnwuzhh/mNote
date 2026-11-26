import 'package:material_ui/material_ui.dart';

/// Design tokens of the "页边" design (design-demos/final.html).
@immutable
class MnotePalette extends ThemeExtension<MnotePalette> {
  const new({
    required this.dark,
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
ThemeData mnoteTheme(ThemeData base, {required bool night}) {
  final p = night ? MnotePalette.night : MnotePalette.light;
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

/// Global night-mode switch for mNote screens (top-bar moon icon).
final mnoteNight = ValueNotifier<bool>(false);

/// Wraps [child] in the mNote theme and rebuilds on night-mode changes.
class MnoteThemed extends StatelessWidget {
  const new({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: mnoteNight,
      builder: (context, night, _) => Theme(
        data: mnoteTheme(Theme.of(context), night: night),
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
