import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/pnip_schedule_entry.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_assessment.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/vaccination_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/child_profile_screen.dart';

class _Vaccinations extends Fake implements VaccinationRepository {
  final bool empty;
  _Vaccinations(this.empty);
  @override
  Future<VaccinationAssessment> assessChild(ChildProfile child) async =>
      VaccinationAssessment(
        child: child,
        history: [],
        status: VaccinationAssessmentStatus.notDue,
        recommendedDoses: [],
        message: '',
        schedule: empty
            ? []
            : [
                for (final (name, status) in [
                  ('Future one', PnipDoseStatus.upcoming),
                  ('Future two', PnipDoseStatus.upcoming),
                  ('Past dose', PnipDoseStatus.completed),
                ])
                  PnipScheduleEntry(
                    vaccineId: name,
                    vaccineName: name,
                    doseNumber: 1,
                    scheduledDate: DateTime(2030),
                    status: status,
                  ),
              ],
      );
}

void main() {
  for (final empty in [false, true]) {
    for (final section in ChildProfileSection.values) {
      testWidgets('Child section $section handles empty=$empty', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChildProfileScreen(
              child: ChildProfile(
                id: 'child',
                fullName: 'Test Child',
                birthDate: DateTime(2026),
                sex: 'Female',
                qrIdentifier: 'QR-child',
                relationship: 'Mother',
              ),
              initialSection: section,
              repository: _Vaccinations(empty),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (section == ChildProfileSection.history) {
          expect(
            find.text('No vaccination records found.').hitTestable(),
            findsOneWidget,
          );
        } else if (empty) {
          expect(
            find.text('No upcoming doses scheduled.').hitTestable(),
            findsOneWidget,
          );
        } else {
          expect(
            find.text('Upcoming Schedule (2)').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Future one Dose 1'), findsOneWidget);
          expect(find.text('Future two Dose 1'), findsOneWidget);
          expect(find.text('Past dose Dose 1'), findsNothing);
          await tester.tap(find.widgetWithText(FilterChip, 'Upcoming only'));
          await tester.pumpAndSettle();
          expect(find.text('Past dose Dose 1'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
