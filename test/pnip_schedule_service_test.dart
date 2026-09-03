import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/pnip_schedule_entry.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_record.dart';
import 'package:qr_code_based_pediatric_vaccination/services/pnip_schedule_service.dart';

void main() {
  const service = PnipScheduleService();
  final child = ChildProfile(
    id: 'CH-TEST-SCHEDULE',
    fullName: 'Schedule Test Child',
    birthDate: DateTime(2026, 1, 1),
    sex: 'Female',
    qrIdentifier: 'QR-TEST-SCHEDULE',
    relationship: 'Mother',
  );

  test('marks the first missed series dose overdue', () {
    final schedule = service.calculate(
      child: child,
      history: const [],
      asOf: DateTime(2026, 8, 26),
    );
    final penta1 = schedule.firstWhere(
      (entry) => entry.vaccineId == 'pentavalent' && entry.doseNumber == 1,
    );
    final penta2 = schedule.firstWhere(
      (entry) => entry.vaccineId == 'pentavalent' && entry.doseNumber == 2,
    );
    expect(penta1.status, PnipDoseStatus.overdue);
    expect(penta2.status, PnipDoseStatus.notEligible);
  });

  test('All ages retain fifteen doses including IPV2 at nine months', () {
    for (final age in [0, 42, 300, 500]) {
      final schedule = service.calculate(
        child: child,
        history: const [],
        asOf: child.birthDate.add(Duration(days: age)),
      );
      expect(schedule.length, 15);
      final ipv2 = schedule.singleWhere(
        (e) => e.vaccineId == 'ipv' && e.doseNumber == 2,
      );
      expect(ipv2.scheduledDate, DateTime(2026, 10, 1));
      expect(ipv2.status, PnipDoseStatus.notEligible);
    }
  });

  test('Delayed IPV1 keeps IPV2 at least four months later', () {
    final record = VaccinationRecord(
      id: 'ipv-test',
      recordCode: 'IPV-TEST',
      childId: child.id,
      vaccineId: 'ipv',
      vaccineName: 'IPV',
      doseNumber: 1,
      dateAdministered: DateTime(2026, 8, 31),
      administeringFacility: 'Test',
      healthWorkerName: 'Test',
      source: VaccinationSource.bugo,
      notes: '',
      recordedAt: DateTime(2026, 8, 31),
    );
    final schedule = service.calculate(
      child: child,
      history: [record],
      asOf: DateTime(2026, 10, 1),
    );
    final ipv2 = schedule.singleWhere(
      (e) => e.vaccineId == 'ipv' && e.doseNumber == 2,
    );
    expect(ipv2.scheduledDate, DateTime(2026, 12, 31));
    expect(ipv2.status, PnipDoseStatus.upcoming);
  });

  test('uses a four-week minimum interval after a delayed dose', () {
    final delayedDose = VaccinationRecord(
      id: '00000000-0000-4000-9000-999999999999',
      recordCode: 'VAX-2026-999999',
      childId: child.id,
      vaccineId: 'pentavalent',
      vaccineName: 'Pentavalent',
      doseNumber: 1,
      dateAdministered: DateTime(2026, 8, 1),
      administeringFacility: 'Test Health Center',
      healthWorkerName: 'Test Worker',
      source: VaccinationSource.bugo,
      notes: '',
      recordedAt: DateTime(2026, 8, 1),
    );
    final schedule = service.calculate(
      child: child,
      history: [delayedDose],
      asOf: DateTime(2026, 8, 10),
    );
    final penta2 = schedule.firstWhere(
      (entry) => entry.vaccineId == 'pentavalent' && entry.doseNumber == 2,
    );
    expect(penta2.status, PnipDoseStatus.upcoming);
    expect(penta2.scheduledDate, DateTime(2026, 8, 29));
  });
}
