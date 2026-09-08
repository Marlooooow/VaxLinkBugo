import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_assessment.dart';
import '../models/vaccination_record.dart';
import '../repositories/vaccination_repository.dart';
import '../services/mock_identifier_generator.dart';
import '../services/session_context.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';

class PreviousVaccinationScreen extends StatefulWidget {
  final ChildProfile child;

  const PreviousVaccinationScreen({super.key, required this.child});

  @override
  State<PreviousVaccinationScreen> createState() =>
      _PreviousVaccinationScreenState();
}

class _PreviousVaccinationScreenState extends State<PreviousVaccinationScreen> {
  final VaccinationRepository _repository =
      RepositoryRegistry.instance.vaccinationRepository;
  final _facility = TextEditingController();
  final _healthWorker = TextEditingController();
  final _notes = TextEditingController();
  late Future<VaccinationAssessment> _assessment;
  PnipScheduleEntry? _selectedDose;
  DateTime? _dateAdministered;
  String _evidenceType = 'Vaccination card';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _assessment = _repository.assessChild(widget.child);
  }

  @override
  void dispose() {
    _facility.dispose();
    _healthWorker.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _selectDate() async {
    final dose = _selectedDose;
    if (dose == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the vaccine dose first.')),
      );
      return;
    }
    final today = DateTime.now();
    final initial = _dateAdministered ?? today;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(dose.scheduledDate)
          ? dose.scheduledDate
          : initial,
      firstDate: dose.scheduledDate,
      lastDate: today,
      helpText: 'SELECT PREVIOUS ADMINISTRATION DATE',
    );
    if (selected != null) setState(() => _dateAdministered = selected);
  }

  Future<void> _save() async {
    final dose = _selectedDose;
    if (dose == null || _dateAdministered == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a dose and administration date.')),
      );
      return;
    }
    if (_facility.text.trim().isEmpty || _healthWorker.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the administering facility and health worker.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final identity = MockIdentifierGenerator.next(prefix: 'VAX');
      await _repository.recordVaccinations([
        VaccinationRecord(
          id: identity.id,
          recordCode: identity.code,
          childId: widget.child.id,
          vaccineId: dose.vaccineId,
          vaccineName: dose.vaccineName,
          doseNumber: dose.doseNumber,
          dateAdministered: _dateAdministered!,
          administeringFacility: _facility.text.trim(),
          healthWorkerName: _healthWorker.text.trim(),
          source: VaccinationSource.previousRecord,
          evidenceType: _evidenceType,
          notes: _notes.text.trim(),
          recordedAt: DateTime.now(),
          recordedByUserId: SessionContext.userId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _selectedDose = null;
        _dateAdministered = null;
        _facility.clear();
        _healthWorker.clear();
        _notes.clear();
        _assessment = _repository.assessChild(widget.child);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Previous vaccination record added.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The previous vaccination record could not be saved. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Previous Vaccinations',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: FutureBuilder<VaccinationAssessment>(
      future: _assessment,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppLoadingView(
            title: 'Loading vaccination assessment',
            message: 'Preparing the saved history and eligible schedule.',
          );
        }
        final assessment = snapshot.data!;
        final eligibleMissing = assessment.schedule
            .where((entry) => entry.requiresAction)
            .toList(growable: false);
        final nextRequired = assessment.recommendedDoses.isEmpty
            ? null
            : assessment.recommendedDoses.first;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
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
                'Record only doses supported by a vaccination card, signed record, or health-facility record. Add each prior visit separately when dates or facilities differ.',
                style: TextStyle(height: 1.4),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${assessment.history.length} previous dose(s) recorded',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (assessment.history.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ScheduleResultCard(
                nextRequired: nextRequired,
                formatDate: _date,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<PnipScheduleEntry>(
              initialValue: _selectedDose,
              decoration: const InputDecoration(labelText: 'Vaccine dose'),
              items: eligibleMissing
                  .map(
                    (dose) => DropdownMenuItem(
                      value: dose,
                      child: Text(
                        '${dose.vaccineName} Dose ${dose.doseNumber}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedDose = value;
                _dateAdministered = null;
              }),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date administered',
                  suffixIcon: Icon(Icons.calendar_month_rounded),
                ),
                child: Text(
                  _dateAdministered == null
                      ? 'Select date'
                      : _date(_dateAdministered!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _facility,
              decoration: const InputDecoration(
                labelText: 'Administering facility',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _healthWorker,
              decoration: const InputDecoration(labelText: 'Health worker'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _evidenceType,
              decoration: const InputDecoration(labelText: 'Evidence source'),
              items:
                  const [
                        'Vaccination card',
                        'Signed vaccination record',
                        'Health facility record',
                      ]
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _evidenceType = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Verification notes (optional)',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving || eligibleMissing.isEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Previous Dose'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: assessment.history.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Finish & Review Updated Schedule'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back Without Finishing'),
            ),
          ],
        );
      },
    ),
  );
}

class _ScheduleResultCard extends StatelessWidget {
  final PnipScheduleEntry? nextRequired;
  final String Function(DateTime) formatDate;

  const _ScheduleResultCard({
    required this.nextRequired,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.green.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule recalculated',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  nextRequired == null
                      ? 'No vaccine dose currently requires action.'
                      : 'Next: ${nextRequired!.vaccineName} Dose ${nextRequired!.doseNumber} • ${formatDate(nextRequired!.scheduledDate)}',
                  style: TextStyle(color: primary, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
