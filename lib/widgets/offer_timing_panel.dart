import 'package:flutter/material.dart';
import '../models/appointment_slot_offer.dart';

class OfferTimingPanel extends StatelessWidget {
  final AppointmentSlotOffer offer;
  const OfferTimingPanel({super.key, required this.offer});
  String _when(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final format = MaterialLocalizations.of(context);
    final date = format.formatMediumDate(local);
    return '$date • ${local.hour == 0 && local.minute == 0 ? "Time not assigned" : format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Current appointment: ${_when(context, offer.currentAppointmentDate)}',
      ),
      const SizedBox(height: 8),
      Text(
        'Earlier appointment: ${_when(context, offer.offeredAppointmentDate)}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Colors.green.shade800,
        ),
      ),
      const SizedBox(height: 8),
      if (offer.status == AppointmentSlotOfferStatus.pending) ...[
        Text(
          'Respond by: ${_when(context, offer.expiresAt)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Slot and one dose provisionally held in the offer queue. Stock is checked again when you accept.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Your current appointment stays unchanged until you accept.',
        ),
      ],
      const SizedBox(height: 8),
      Text('Queue order: ${offer.queueReason}'),
      if (offer.respondedAt != null)
        Text(
          'Response: ${offer.responseChannel == "staff_recorded" ? "Recorded by health worker" : "Guardian online"}',
        ),
    ],
  );
}
