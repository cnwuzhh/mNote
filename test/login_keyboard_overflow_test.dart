import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/pages/user/login.dart';

/// Regression test: landscape tablet (iQOO Pad, 1280x837 dp) with the soft
/// keyboard open must not overflow the two-column Nextcloud login step.
void main() {
  setUp(FlavorConfig.setup);

  testWidgets('NcLoginStep does not overflow with keyboard in landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1280 * 3, 837.3 * 3);
    tester.view.viewInsets = const FakeViewPadding(bottom: 380 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SaberTheme.createThemeFromSeed(
          Colors.yellow,
          .light,
          TargetPlatform.android,
        ),
        home: const NcLoginPage(forceCurrentStep: .nc),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  // BUG-2 (device test TC-LOGIN-02 step 3): dragging the page down must close
  // the keyboard, including when the page is at the top and does not scroll.
  for (final landscape in [true, false]) {
    testWidgets(
      'drag and tap close the keyboard (${landscape ? 'landscape' : 'portrait'})',
      (tester) async {
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = landscape
            ? const Size(1280 * 3, 837.3 * 3)
            : const Size(837.3 * 3, 1280 * 3);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: SaberTheme.createThemeFromSeed(
              Colors.yellow,
              .light,
              TargetPlatform.android,
            ),
            home: const NcLoginPage(forceCurrentStep: .nc),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        bool hasFocus() => tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus;

        // Focus the field and simulate the keyboard taking the bottom part.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 380 * 3);
        await tester.pump(const Duration(milliseconds: 300));
        expect(hasFocus(), isTrue);

        // Drag downward starting near the top of the page (pulls past the top).
        final scroll = find.byType(Scrollable).first;
        final top = tester.getTopLeft(scroll) + const Offset(200, 40);
        await tester.dragFrom(top, const Offset(0, 260));
        await tester.pumpAndSettle();
        expect(hasFocus(), isFalse, reason: 'drag down closes the keyboard');

        // Tap the field again, then tap a blank area.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(hasFocus(), isTrue);
        await tester.tapAt(tester.getTopLeft(scroll) + const Offset(20, 20));
        await tester.pump();
        expect(
          hasFocus(),
          isFalse,
          reason: 'tapping a blank area closes the keyboard',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
