import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/appointment_slot_offer.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_appointment.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/earlier_appointment_offers_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccination_appointments_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

class _Offers extends Fake implements AppointmentRepository {
  final items = [
    for (final status in AppointmentSlotOfferStatus.values)
      AppointmentSlotOffer(
        id: status.name,
        offerCode: 'OFR-${status.name}',
        appointmentId: 'appointment-${status.name}',
        guardianId: 'guardian',
        childId: 'child-${status.name}',
        childName: 'Child ${status.name}',
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        doseNumber: 1,
        currentAppointmentDate: DateTime(2026, 9, 10),
        offeredAppointmentDate: DateTime(2026, 9, 7, 9),
        status: status,
        createdAt: DateTime(2026, 9, 5),
        expiresAt: DateTime(2026, 9, 6, 12),
        respondedAt: null,
      ),
  ];
  @override
  Future<List<AppointmentSlotOffer>> getGuardianSlotOffers(String id) async =>
      items;
  @override
  Future<List<AppointmentSlotOffer>> getFacilitySlotOffers() async => items;
  @override
  Future<List<VaccinationAppointment>> getGuardianAppointments(
    String id,
  ) async => [];
  @override
  Future<VaccinationAppointment?> respondToSlotOffer(
    String id,
    bool accept,
    String userId, {
    String responseChannel = 'guardian_online',
  }) async {
    final index = items.indexWhere((o) => o.id == id);
    items[index] = items[index].copyWith(
      status: accept
          ? AppointmentSlotOfferStatus.accepted
          : AppointmentSlotOfferStatus.declined,
    );
    return null;
  }
}

void main() {
  testWidgets(
    'Appointments shows compact shortcut and opens separate filtered offers',
    (tester) async {
      final repository = _Offers();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: VaccinationAppointmentsScreen.guardian(
            guardianId: 'guardian',
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Child pending'), findsNothing);
      expect(find.text('1 awaiting response'), findsOneWidget);
      await tester.tap(find.text('Earlier appointment offers'));
      await tester.pumpAndSettle();
      expect(find.byType(EarlierAppointmentOffersScreen), findsOneWidget);
      expect(find.text('Child pending'), findsOneWidget);
      expect(find.text('Child accepted'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Accepted'));
      await tester.pumpAndSettle();
      expect(find.text('Child accepted'), findsOneWidget);
      expect(find.text('Child pending'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Specific offer opens expanded on narrow phone and choice refreshes status',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: EarlierAppointmentOffersScreen(
            healthWorkerMode: false,
            guardianId: 'guardian',
            initialOfferId: 'pending',
            repository: _Offers(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Child pending'), findsOneWidget);
      expect(find.text('Child accepted'), findsNothing);
      await tester.ensureVisible(find.text('Keep current appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep current appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Keep current appointment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Missing offer never falls back to an unrelated offer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EarlierAppointmentOffersScreen(
          healthWorkerMode: true,
          initialOfferId: 'missing',
          repository: _Offers(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This offer is no longer available.'), findsOneWidget);
    expect(find.text('Child pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
