import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/dashboard_stat_grid.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 390.0]) {
        testWidgets(
          'Rectangular overview stats: dark=$dark, text=$scale, width=$width',
          (tester) async {
            tester.view.physicalSize = Size(width, 740);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var tapped = false;
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: DashboardStatGrid(
                        stats: [
                          DashboardStat(
                            'Children due',
                            24,
                            Icons.groups_rounded,
                            Colors.teal,
                            actionLabel: 'View families',
                            onTap: () => tapped = true,
                          ),
                          const DashboardStat(
                            'Vaccines due',
                            1234567,
                            Icons.vaccines_outlined,
                            Colors.teal,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            final icon = find.byIcon(Icons.groups_rounded);
            final number = find.text('24');
            expect(tester.widget<Icon>(icon).size, 30);
            expect(tester.widget<Text>(number).style!.fontSize, 38);
            expect(
              tester.getCenter(icon).dx,
              lessThan(tester.getCenter(number).dx),
            );
            final card = find.ancestor(of: number, matching: find.byType(Card));
            expect(
              tester.getSize(card).width,
              greaterThan(tester.getSize(card).height),
            );
            await tester.tap(number);
            expect(tapped, isTrue);
            await tester.ensureVisible(find.text('1234567'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
