import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/vaccination_appointment.dart';
import '../models/appointment_slot_offer.dart';
import '../repositories/appointment_repository.dart';
import 'appointment_form_screen.dart';
import 'earlier_appointment_offers_screen.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_feedback.dart';
import '../widgets/worker_app_bar_actions.dart';
import '../widgets/guardian_app_bar_actions.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../widgets/bugo_brand_title.dart';

class VaccinationAppointmentsScreen extends StatefulWidget {
  final String? guardianId;
  final bool healthWorkerMode;
  final AppointmentRepository? repository;
  final String? initialAppointmentId;
  final String? waitlistVaccineId;
  final bool waitlistOnly;
  final AppUser? guardianUser;
  final AuthRepository? guardianAuthRepository;

  const VaccinationAppointmentsScreen.guardian({
    super.key,
    required this.guardianId,
    this.repository,
    this.initialAppointmentId,
    this.guardianUser,
    this.guardianAuthRepository,
  }) : healthWorkerMode = false,
       waitlistVaccineId = null,
       waitlistOnly = false;

  const VaccinationAppointmentsScreen.healthWorker({
    super.key,
    this.repository,
    this.initialAppointmentId,
    this.waitlistVaccineId,
    this.waitlistOnly = false,
    this.guardianUser,
    this.guardianAuthRepository,
  }) : guardianId = null,
       healthWorkerMode = true;

  @override
  State<VaccinationAppointmentsScreen> createState() =>
      _VaccinationAppointmentsScreenState();
}

class _VaccinationAppointmentsScreenState
    extends State<VaccinationAppointmentsScreen> {
  late final AppointmentRepository _repository;
  late Future<List<VaccinationAppointment>> _appointments;
  late Future<int> _pendingOfferCount;
  final List<VaccinationAppointment> _loadedAppointments = [];
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ?? RepositoryRegistry.instance.appointmentRepository;
    _reload();
  }

  void _reload() {
    _nextOffset = 0;
    _hasMore = false;
    _totalCount = 0;
    _appointments = _loadAppointmentPage(reset: true);
    _pendingOfferCount = widget.healthWorkerMode
        ? _repository
              .getFacilitySlotOffersPage(
                status: AppointmentSlotOfferStatus.pending,
                limit: 1,
              )
              .then((page) => page.pendingCount)
        : _repository
              .getGuardianSlotOffersPage(
                widget.guardianId!,
                status: AppointmentSlotOfferStatus.pending,
                limit: 1,
              )
              .then((page) => page.pendingCount);
  }

  Future<List<VaccinationAppointment>> _loadAppointmentPage({
    required bool reset,
  }) async {
    final page = widget.healthWorkerMode
        ? await _repository.getFacilityAppointmentsPage(
            initialAppointmentId: widget.initialAppointmentId,
            waitlistVaccineId: widget.waitlistVaccineId,
            waitlistOnly: widget.waitlistOnly,
            limit: 20,
            offset: reset ? 0 : _nextOffset,
          )
        : await _repository.getGuardianAppointmentsPage(
            widget.guardianId!,
            initialAppointmentId: widget.initialAppointmentId,
            limit: 20,
            offset: reset ? 0 : _nextOffset,
          );
    if (reset) _loadedAppointments.clear();
    final ids = _loadedAppointments.map((item) => item.id).toSet();
    _loadedAppointments.addAll(page.items.where((item) => ids.add(item.id)));
    _hasMore = page.hasMore;
    _nextOffset = page.nextOffset;
    _totalCount = page.totalCount;
    return List.unmodifiable(_loadedAppointments);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await _loadAppointmentPage(reset: false);
      if (mounted) {
        setState(() {
          _appointments = Future.value(items);
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _reschedule(VaccinationAppointment appointment) async {
    final result = await Navigator.push<VaccinationAppointment>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentFormScreen.reschedule(
          repository: _repository,
          existingAppointment: appointment,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(_reload);
      AppFeedback.success(
        context,
        message: 'Appointment rescheduled successfully.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: widget.healthWorkerMode
          ? const Text(
              'Vaccination Appointments',
              style: TextStyle(fontWeight: FontWeight.w800),
            )
          : const BugoBrandTitle(),
      actions: widget.healthWorkerMode
          ? const [WorkerAppBarActions()]
          : [
              GuardianAppBarActions(
                user: widget.guardianUser,
                authRepository: widget.guardianAuthRepository,
              ),
            ],
    ),
    body: FutureBuilder<List<VaccinationAppointment>>(
      future: _appointments,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingView(
            title: 'Loading appointments',
            message: 'Retrieving scheduled and waitlisted visits.',
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Appointments could not be loaded. Please go back and try again.',
            ),
          );
        }
        final items = (snapshot.data ?? const <VaccinationAppointment>[])
            .where(
              (item) =>
                  (!widget.waitlistOnly ||
                      item.status == VaccinationAppointmentStatus.waitlisted) &&
                  (widget.initialAppointmentId == null ||
                      item.id == widget.initialAppointmentId) &&
                  (widget.waitlistVaccineId == null ||
                      (item.vaccineId == widget.waitlistVaccineId &&
                          item.status ==
                              VaccinationAppointmentStatus.waitlisted)),
            )
            .toList();
        if (widget.waitlistOnly || widget.waitlistVaccineId != null) {
          items.sort((a, b) {
            final priority = b.clinicalPriority.compareTo(a.clinicalPriority);
            return priority != 0
                ? priority
                : a.createdAt.compareTo(b.createdAt);
          });
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'Appointment dates organize service delivery. PNIP due dates remain unchanged.',
                style: TextStyle(height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<int>(
              future: _pendingOfferCount,
              builder: (context, snapshot) {
                final pending = snapshot.data ?? 0;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('Earlier appointment offers'),
                    subtitle: Text(
                      snapshot.hasError
                          ? 'Open to retry loading offers'
                          : snapshot.connectionState == ConnectionState.waiting
                          ? 'Checking offers…'
                          : '$pending awaiting response',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EarlierAppointmentOffersScreen(
                            healthWorkerMode: widget.healthWorkerMode,
                            guardianId: widget.guardianId,
                            repository: _repository,
                          ),
                        ),
                      );
                      if (mounted) setState(_reload);
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    widget.initialAppointmentId != null
                        ? 'This appointment is no longer available.'
                        : widget.waitlistVaccineId != null
                        ? 'No patients are currently waiting for this vaccine.'
                        : 'No appointments or waitlist entries yet.',
                  ),
                ),
              )
            else
              ...items.map(
                (item) => _AppointmentCard(
                  item: item,
                  canReschedule:
                      widget.healthWorkerMode &&
                      (item.status == VaccinationAppointmentStatus.scheduled ||
                          item.status ==
                              VaccinationAppointmentStatus.confirmed ||
                          item.status ==
                              VaccinationAppointmentStatus.waitlisted),
                  onReschedule: () => _reschedule(item),
                ),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Showing ${items.length} of $_totalCount appointments',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              if (_loadingMore)
                const Center(child: CircularProgressIndicator())
              else if (_hasMore)
                OutlinedButton.icon(
                  onPressed: _loadMore,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('Load 20 more'),
                )
              else
                const Center(child: Text('All appointments are loaded.')),
            ],
          ],
        );
      },
    ),
  );
}

class _AppointmentCard extends StatelessWidget {
  final VaccinationAppointment item;
  final bool canReschedule;
  final VoidCallback onReschedule;

  const _AppointmentCard({
    required this.item,
    required this.canReschedule,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.10),
          child: Icon(Icons.event_outlined, color: color),
        ),
        title: Text(
          item.childName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${item.vaccineName} Dose ${item.doseNumber}\n'
          '${_statusLabel(item.status)} • ${_appointmentTime(item.appointmentDate)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          _row('PNIP due date', _date(item.pnipDueDate)),
          _row(
            'Appointment date and time',
            _appointmentTime(item.appointmentDate),
          ),
          _row('Facility', item.facilityName),
          _row('Reason', item.reason),
          _row('Appointment ID', item.appointmentCode),
          _row('Queue entry', _date(item.createdAt)),
          _row(
            'Priority',
            item.clinicalPriority > 0
                ? 'Staff-assigned clinical priority'
                : 'Standard waiting-list order',
          ),
          if (canReschedule) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReschedule,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('Reschedule Appointment'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 115,
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

String _statusLabel(VaccinationAppointmentStatus status) => switch (status) {
  VaccinationAppointmentStatus.scheduled => 'Scheduled',
  VaccinationAppointmentStatus.confirmed => 'Confirmed',
  VaccinationAppointmentStatus.checkedIn => 'Checked in',
  VaccinationAppointmentStatus.completed => 'Completed',
  VaccinationAppointmentStatus.cancelled => 'Cancelled',
  VaccinationAppointmentStatus.noShow => 'No show',
  VaccinationAppointmentStatus.rescheduled => 'Rescheduled',
  VaccinationAppointmentStatus.waitlisted => 'Priority waitlist',
  VaccinationAppointmentStatus.referred => 'Referred',
};

Color _statusColor(VaccinationAppointmentStatus status) => switch (status) {
  VaccinationAppointmentStatus.scheduled ||
  VaccinationAppointmentStatus.confirmed => Colors.blue,
  VaccinationAppointmentStatus.checkedIn => Colors.orange,
  VaccinationAppointmentStatus.completed => Colors.green,
  VaccinationAppointmentStatus.waitlisted => Colors.deepOrange,
  VaccinationAppointmentStatus.rescheduled => Colors.purple,
  VaccinationAppointmentStatus.cancelled ||
  VaccinationAppointmentStatus.noShow ||
  VaccinationAppointmentStatus.referred => Colors.grey,
};

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.year}';

String _appointmentTime(DateTime value) =>
    '${_date(value)} • ${value.hour == 0 && value.minute == 0 ? "Time not assigned" : "${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}"}';
