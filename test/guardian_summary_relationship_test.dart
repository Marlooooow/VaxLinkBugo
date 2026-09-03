import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/pnip_schedule_entry.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/child_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/vaccination_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/guardian_dashboard_children.dart';

final _cases = [
  ('Mother', 'Female', 'Daughter'),
  ('Mother', 'Male', 'Son'),
  ('Father', 'Female', 'Daughter'),
  ('Father', 'Male', 'Son'),
  ('Aunt', 'Male', 'Nephew'),
  ('Aunt', 'Female', 'Niece'),
  ('Uncle', 'Male', 'Nephew'),
  ('Uncle', 'Female', 'Niece'),
  ('Grandmother', 'Female', 'Granddaughter'),
  ('Grandmother', 'Male', 'Grandson'),
  ('Grandfather', 'Female', 'Granddaughter'),
  ('Grandfather', 'Male', 'Grandson'),
  ('Brother', 'Female', 'Sister'),
  ('Brother', 'Male', 'Brother'),
  ('Sister', 'Female', 'Sister'),
  ('Sister', 'Male', 'Brother'),
  ('Legal Guardian', 'Female', 'Under your care'),
  ('Legal Guardian', 'Male', 'Under your care'),
  (' aunt ', ' female ', 'Niece'),
];

class _Children extends Fake implements ChildRepository {
  @override
  Future<List<ChildProfile>> getChildrenForGuardian(String id) async => [
    for (var i = 0; i < _cases.length; i++)
      ChildProfile(
        id: 'child-$i',
        fullName: 'Child $i',
        birthDate: DateTime(2026),
        sex: _cases[i].$2,
        relationship: _cases[i].$1,
        qrIdentifier: 'QR-$i',
      ),
  ];
}

class _Vaccinations extends Fake implements VaccinationRepository {
  @override
  Future<List<PnipScheduleEntry>> getVaccinationSchedule(
    ChildProfile child,
  ) async => [];
}

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      for (final width in [320.0, 390.0]) {
        testWidgets(
          'Selected-child relationship stays inline; dark=$dark scale=$scale width=$width',
          (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: GuardianDashboardChildren(
                        guardianId: 'guardian',
                        children: _Children(),
                        vaccinations: _Vaccinations(),
                        onChanged: () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (var i = 0; i < _cases.length; i++) {
              tester
                  .widget<DropdownButton<String>>(
                    find.byType(DropdownButton<String>),
                  )
                  .onChanged!('child-$i');
              await tester.pumpAndSettle();
              final badge = find.byKey(
                const ValueKey('selected-child-relationship'),
              );
              expect(
                find.descendant(of: badge, matching: find.text(_cases[i].$3)),
                findsOneWidget,
              );
              final tooltip = tester.widget<Tooltip>(
                find.ancestor(of: badge, matching: find.byType(Tooltip)),
              );
              expect(
                tooltip.message,
                'Your relationship to Child $i: ${_cases[i].$1}',
              );
              expect(tester.getTopRight(badge).dx, closeTo(width - 32, .01));
              final heading = find.text('Child summary');
              expect(
                tester.getCenter(badge).dy,
                closeTo(tester.getCenter(heading).dy, .01),
              );
              expect(
                tester.getTopLeft(badge).dx,
                greaterThan(tester.getTopRight(heading).dx),
              );
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
}
