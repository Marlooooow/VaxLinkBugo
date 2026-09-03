import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/family_care_banner.dart';

void main() {
  testWidgets('Family banner fits a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: FamilyCareBanner(),
            ),
          ),
        ),
      ),
    );
    // The dashboard title/subtitle were intentionally removed. Keep this
    // regression focused on responsive layout rather than deleted copy.
    expect(find.byType(FamilyCareBanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Primary action text has accessible contrast', () {
    final contrast = 1.05 / (AppTheme.primaryTeal.computeLuminance() + .05);
    expect(contrast, greaterThanOrEqualTo(4.5));
    expect(AppTheme.lightTheme.cardTheme.color, Colors.white);
  });
}
