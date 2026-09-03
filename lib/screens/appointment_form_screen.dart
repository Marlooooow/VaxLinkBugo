import 'package:flutter/material.dart';

import '../models/vaccination_appointment.dart';
import '../models/vaccination_reminder.dart';
import '../repositories/appointment_repository.dart';
import '../services/mock_scenario_clock.dart';
import '../services/session_context.dart';

class AppointmentFormScreen extends StatefulWidget {
  final AppointmentRepository repository;
  final VaccinationReminder? reminder;
  final VaccinationAppointment? existingAppointment;

  const AppointmentFormScreen.schedule({
    super.key,
    required this.repository,
    required VaccinationReminder this.reminder,
  }) : existingAppointment = null;

  const AppointmentFormScreen.reschedule({
    super.key,
    required this.repository,
    required VaccinationAppointment this.existingAppointment,
  }) : reminder = null;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  final _reason = TextEditingController();
  DateTime? _appointmentDate;
  bool _waitlist = false;
  String? _dateError;
  String? _reasonError;
  bool _saving = false;

  bool get _isReschedule => widget.existingAppointment != null;
  DateTime get _pnipDueDate =>
      widget.reminder?.dueDate ?? widget.existingAppointment!.pnipDueDate;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final first = MockScenarioClock.today.isAfter(_pnipDueDate)
        ? MockScenarioClock.today
        : _pnipDueDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: _appointmentDate ?? first,
      firstDate: first,
      lastDate: DateTime(first.year + 2, 12, 31),
      helpText: _isReschedule
          ? 'SELECT NEW APPOINTMENT DATE'
          : 'SELECT APPOINTMENT DATE',
    );
    if (selected != null) {
      setState(() {
        _appointmentDate = selected;
        _dateError = null;
      });
    }
  }

  Future<void> _submit() async {
    final dateMissing = _appointmentDate == null;
    final reasonMissing = _reason.text.trim().isEmpty;
    setState(() {
      _dateError = dateMissing ? 'Select an appointment date.' : null;
      _reasonError = reasonMissing ? 'Enter the reason for this action.' : null;
    });
    if (dateMissing || reasonMissing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _isReschedule
              ? 'Confirm Rescheduling'
              : _waitlist
              ? 'Confirm Waitlist'
              : 'Confirm Appointment',
        ),
        content: Text(
          'PNIP due date: ${_date(_pnipDueDate)}\n'
          '${_waitlist ? 'Preferred date' : 'Appointment date'}: ${_date(_appointmentDate!)}\n\n'
          'The PNIP due date will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back to edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      late final VaccinationAppointment result;
      if (_isReschedule) {
        result = await widget.repository.reschedule(
          RescheduleAppointmentRequest(
            appointmentId: widget.existingAppointment!.id,
            newAppointmentDate: _appointmentDate!,
            reason: _reason.text.trim(),
            rescheduledByUserId: SessionContext.userId,
          ),
        );
      } else {
        final reminder = widget.reminder!;
        final request = AppointmentRequest(
          guardianId: reminder.guardianId,
          reminderId: reminder.id,
          childId: reminder.childId,
          childName: reminder.childName,
          vaccineId: reminder.vaccineId,
          vaccineName: reminder.vaccineName,
          doseNumber: reminder.doseNumber,
          pnipDueDate: reminder.dueDate,
          appointmentDate: _appointmentDate!,
          source: _waitlist
              ? VaccinationAppointmentSource.stockDeferral
              : VaccinationAppointmentSource.pnipReminder,
          reason: _reason.text.trim(),
          createdByUserId: SessionContext.userId,
        );
        result = _waitlist
            ? await widget.repository.addToWaitlist(request)
            : await widget.repository.schedule(request);
      }
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error
                .toString()
                .replaceFirst('Invalid argument(s): ', '')
                .replaceFirst('Bad state: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final childName =
        widget.reminder?.childName ?? widget.existingAppointment!.childName;
    final vaccineName =
        widget.reminder?.vaccineName ?? widget.existingAppointment!.vaccineName;
    final doseNumber =
        widget.reminder?.doseNumber ?? widget.existingAppointment!.doseNumber;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isReschedule ? 'Reschedule Appointment' : 'Schedule Appointment',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  childName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$vaccineName Dose $doseNumber'),
                const SizedBox(height: 5),
                Text('PNIP due date: ${_date(_pnipDueDate)}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!_isReschedule)
            SwitchListTile.adaptive(
              value: _waitlist,
              onChanged: (value) => setState(() => _waitlist = value),
              title: const Text('Add to priority waitlist'),
              subtitle: const Text(
                'Use when stock or session capacity is unavailable.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _selectDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _waitlist
                    ? 'Preferred appointment date'
                    : 'Appointment date',
                errorText: _dateError,
                suffixIcon: const Icon(Icons.calendar_month_outlined),
              ),
              child: Text(
                _appointmentDate == null
                    ? 'Select date'
                    : _date(_appointmentDate!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) {
              if (_reasonError != null) setState(() => _reasonError = null);
            },
            decoration: InputDecoration(
              labelText: _isReschedule
                  ? 'Rescheduling reason'
                  : 'Appointment / waitlist reason',
              hintText: 'Example: Vaccine stock unavailable',
              alignLabelWithHint: true,
              errorText: _reasonError,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Rescheduling changes only the planned visit date. It does not replace the PNIP due date or mark vaccination as completed.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(_saving ? 'Saving...' : 'Review and confirm'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}/'
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.year}';
