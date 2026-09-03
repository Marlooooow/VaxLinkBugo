import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/appointment_slot_offer.dart';
import 'package:qr_code_based_pediatric_vaccination/widgets/offer_timing_panel.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';

void main() {
  testWidgets(
    'Timed offer displays deadline and unchanged original on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final offer = AppointmentSlotOffer(
        id: 'offer',
        offerCode: 'OFR-1',
        appointmentId: 'appointment',
        guardianId: 'guardian',
        childId: 'child',
        childName: 'Child',
        vaccineId: 'bcg',
        vaccineName: 'BCG',
        doseNumber: 1,
        currentAppointmentDate: DateTime(2026, 9, 10),
        offeredAppointmentDate: DateTime(2026, 9, 7, 9, 15),
        status: AppointmentSlotOfferStatus.pending,
        createdAt: DateTime(2026, 9, 5),
        expiresAt: DateTime(2026, 9, 6, 12),
        respondedAt: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: OfferTimingPanel(offer: offer),
            ),
          ),
        ),
      );
      expect(find.textContaining('9:15'), findsOneWidget);
      expect(find.textContaining('Respond by:'), findsOneWidget);
      expect(find.textContaining('Time not assigned'), findsOneWidget);
      expect(
        find.text('Your current appointment stays unchanged until you accept.'),
        findsOneWidget,
      );
      expect(
        AppointmentSlotOffer.fromJson(offer.toJson()).offeredAppointmentDate,
        offer.offeredAppointmentDate,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
