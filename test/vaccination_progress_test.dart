import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/pnip_schedule_entry.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_progress.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/vaccination_progress_bar.dart';

void main() {
  final today = DateTime(2026, 8, 30);
  PnipScheduleEntry entry(
    int dose,
    DateTime date,
    PnipDoseStatus status, {
    DateTime? administered,
  }) => PnipScheduleEntry(
    vaccineId: 'test',
    vaccineName: 'Test vaccine',
    doseNumber: dose,
    scheduledDate: date,
    status: status,
    administeredDate: administered,
  );

  test('Full total includes future doses and deduplicates', () {
    final completed = entry(
      1,
      DateTime(2026, 7, 1),
      PnipDoseStatus.completed,
      administered: DateTime(2026, 7, 1),
    );
    final result = VaccinationProgress.fromSchedule([
      completed,
      completed,
      entry(2, DateTime(2026, 8, 1), PnipDoseStatus.overdue),
      entry(3, DateTime(2026, 9, 1), PnipDoseStatus.upcoming),
    ], asOf: today);
    expect(result.completed, 1);
    expect(result.totalDoses, 3);
    expect(result.fraction, closeTo(1 / 3, .0001));
    expect(result.overdue, 1);
    expect(result.upcoming, 1);
  });

  test('Empty and future-only schedules do not claim full completion', () {
    expect(VaccinationProgress.fromSchedule([], asOf: today).fraction, 0);
    final result = VaccinationProgress.fromSchedule([
      entry(1, DateTime(2027), PnipDoseStatus.upcoming),
    ], asOf: today);
    expect(result.totalDoses, 1);
    expect(result.fraction, 0);
  });

  test('Future administration is not counted as recorded completion today', () {
    final result = VaccinationProgress.fromSchedule([
      entry(
        1,
        DateTime(2026, 8, 1),
        PnipDoseStatus.completed,
        administered: DateTime(2026, 9, 1),
      ),
    ], asOf: today);
    expect(result.completed, 0);
  });

  testWidgets('Progress fits narrow screens and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: VaccinationProgressBar(
                schedule: [
                  entry(
                    1,
                    DateTime(2020),
                    PnipDoseStatus.completed,
                    administered: DateTime(2020),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
