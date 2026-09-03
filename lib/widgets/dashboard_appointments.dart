import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';
import '../models/vaccination_appointment.dart';
import '../repositories/appointment_repository.dart';
import '../screens/vaccination_appointments_screen.dart';

class DashboardAppointments extends StatefulWidget {
  final String? guardianId;
  final AppointmentRepository? repository;
  final VoidCallback onChanged;
  final int revision;
  const DashboardAppointments({
    super.key,
    this.guardianId,
    this.repository,
    required this.onChanged,
    this.revision = 0,
  });
  @override
  State<DashboardAppointments> createState() => _DashboardAppointmentsState();
}

class _DashboardAppointmentsState extends State<DashboardAppointments> {
  late Future<List<VaccinationAppointment>> _rows;
  late AppointmentRepository _repository;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardAppointments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guardianId != widget.guardianId ||
        oldWidget.repository != widget.repository ||
        oldWidget.revision != widget.revision) {
      _load();
    }
  }

  void _load() {
    _repository = widget.repository ?? RepositoryRegistry.instance.appointmentRepository;
    _rows = widget.guardianId == null
        ? _repository.getFacilityAppointments()
        : _repository.getGuardianAppointments(widget.guardianId!);
  }

  Future<void> _open([String? id]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => widget.guardianId == null
            ? VaccinationAppointmentsScreen.healthWorker(
                initialAppointmentId: id,
                repository: _repository,
              )
            : VaccinationAppointmentsScreen.guardian(
                guardianId: widget.guardianId!,
                initialAppointmentId: id,
                repository: _repository,
              ),
      ),
    );
    if (!mounted) return;
    setState(_load);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next appointments',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          FutureBuilder<List<VaccinationAppointment>>(
            future: _rows,
            builder: (context, snapshot) {
              if (!snapshot.hasData &&
                  snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Loading appointments…'),
                );
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(_load),
                  child: const Text('Retry appointments'),
                );
              }
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final rows =
                  (snapshot.data ?? [])
                      .where(
                        (a) =>
                            !a.appointmentDate.isBefore(today) &&
                            [
                              VaccinationAppointmentStatus.scheduled,
                              VaccinationAppointmentStatus.confirmed,
                              VaccinationAppointmentStatus.checkedIn,
                            ].contains(a.status),
                      )
                      .toList()
                    ..sort(
                      (a, b) => a.appointmentDate.compareTo(b.appointmentDate),
                    );
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'No upcoming appointments. You can still review reminders and waitlist entries.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final a in rows.take(2))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.childName),
                      subtitle: Text(
                        '${a.vaccineName} Dose ${a.doseNumber}\n${MaterialLocalizations.of(context).formatMediumDate(a.appointmentDate)} · ${a.facilityName}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(a.id),
                    ),
                ],
              );
            },
          ),
          TextButton(
            onPressed: _open,
            child: const Text('View all appointments'),
          ),
        ],
      ),
    ),
  );
}
