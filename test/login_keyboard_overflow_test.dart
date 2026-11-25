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
}
