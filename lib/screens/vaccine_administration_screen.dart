import 'package:flutter/material.dart';

import '../models/child/child_profile.dart';
import '../models/vaccine_inventory.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../repositories/repository_registry.dart';
import '../utils/number_formatter.dart';
import '../utils/user_facing_error.dart';
import '../repositories/vaccination_repository.dart';
import '../services/session_context.dart';
import 'referral_screen.dart';
import 'child_profile_screen.dart';

enum _AdministrationResultAction { finishLater, createReferral }

class VaccineAdministrationScreen extends StatefulWidget {
  final ChildProfile child;
  final List<VaccineInventory> vaccines;

  // Vaccines that were due but unavailable at this facility.
  final List<VaccineInventory> unavailableVaccines;

  const VaccineAdministrationScreen({
    super.key,
    required this.child,
    required this.vaccines,
    this.unavailableVaccines = const [],
  });

  @override
  State<VaccineAdministrationScreen> createState() =>
      _VaccineAdministrationScreenState();
}

class _VaccineAdministrationScreenState
    extends State<VaccineAdministrationScreen> {
  final Set<String> _selectedVaccines = {};
  final VaccinationRepository _vaccinationRepository =
      RepositoryRegistry.instance.vaccinationRepository;
  bool _saving = false;
  bool _completed = false;
  bool _historyReviewed = false;
  bool _conditionAssessed = false;
  bool _contraindicationsReviewed = false;
  bool _guardianConsentConfirmed = false;
  final _notAdministeredReason = TextEditingController();

  bool get _screeningComplete =>
      _historyReviewed &&
      _conditionAssessed &&
      _contraindicationsReviewed &&
      _guardianConsentConfirmed;

  @override
  void dispose() {
    _notAdministeredReason.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // All available vaccines are selected by default.
    _selectedVaccines.addAll(
      widget.vaccines.map((vaccine) => vaccine.vaccineId),
    );
  }

  void _confirmAdministration() {
    if (!_screeningComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete the clinical screening checklist first.'),
        ),
      );
      return;
    }
    if (_selectedVaccines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one vaccine.')),
      );
      return;
    }
    if (_selectedVaccines.length < widget.vaccines.length &&
        _notAdministeredReason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Document why a recommended available vaccine was not administered.',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Confirm Administration',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Confirm that the selected vaccine(s) '
            'were administered to ${widget.child.fullName}.',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                _handleSuccessfulAdministration();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSuccessfulAdministration() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final assessment = await _vaccinationRepository.assessChild(widget.child);
      final now = DateTime.now();
      var screening = VaccinationScreening(
        id: '',
        screeningCode: '',
        childId: widget.child.id,
        historyReviewed: _historyReviewed,
        currentConditionAssessed: _conditionAssessed,
        contraindicationsReviewed: _contraindicationsReviewed,
        guardianConsentConfirmed: _guardianConsentConfirmed,
        outcome: VaccinationScreeningOutcome.cleared,
        notes: _notAdministeredReason.text.trim(),
        screenedAt: now,
        screenedByUserId: SessionContext.userId,
      );
      final selectedInventory = widget.vaccines
          .where((item) => _selectedVaccines.contains(item.vaccineId))
          .toList();
      final records = selectedInventory.map((vaccine) {
        final scheduledDose = assessment.recommendedDoses.firstWhere(
          (dose) => dose.vaccineId == vaccine.vaccineId,
        );
        return VaccinationRecord(
          id: '',
          recordCode: '',
          childId: widget.child.id,
          vaccineId: vaccine.vaccineId,
          vaccineName: vaccine.vaccineName,
          doseNumber: scheduledDose.doseNumber,
          dateAdministered: now,
          administeringFacility: 'Barangay Bugo Health Center',
          healthWorkerName: SessionContext.user!.fullName,
          healthWorkerId: SessionContext.userId,
          source: VaccinationSource.bugo,
          notes: 'Recorded through the normal vaccination workflow.',
          recordedAt: now,
          recordedByUserId: SessionContext.userId,
          screeningId: screening.id,
        );
      }).toList();
      await _vaccinationRepository.completeAdministration(
        screening: screening,
        records: records,
        dosesByVaccineId: {
          for (final vaccine in selectedInventory) vaccine.vaccineId: 1,
        },
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _completed = true;
      });
      if (widget.unavailableVaccines.isNotEmpty) {
        final action = await _showPartialAdministrationResult(
          selectedInventory,
        );
        if (!mounted) return;
        if (action == _AdministrationResultAction.createReferral) {
          _openReferral();
        } else if (action == _AdministrationResultAction.finishLater) {
          _openChildProfile(ChildProfileSection.upcoming);
        }
        return;
      }

      await _showAdministrationSuccessDialog(records.length);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'Saving could not be confirmed. Check the vaccination history before trying again.',
            ),
          ),
        ),
      );
      return;
    }
  }

  Future<bool> _showAdministrationSuccessDialog(int recordCount) async {
    var viewedProfile = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vaccination successful',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          '$recordCount vaccination record(s) were saved for '
          '${widget.child.fullName}. The child history and inventory were updated.',
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              viewedProfile = true;
              Navigator.pop(dialogContext);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ChildProfileScreen(
                    child: widget.child,
                    initialSection: ChildProfileSection.history,
                    repository: _vaccinationRepository,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.person_outline_rounded),
            label: const Text('View child profile'),
          ),
        ],
      ),
    );
    return viewedProfile;
  }

  Future<_AdministrationResultAction?> _showPartialAdministrationResult(
    List<VaccineInventory> administeredVaccines,
  ) {
    return showDialog<_AdministrationResultAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vaccination saved',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The administered vaccines were saved for '
                '${widget.child.fullName} and deducted from inventory.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Administered today',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ...administeredVaccines.map(
                (vaccine) => _resultVaccineRow(
                  vaccine.vaccineName,
                  Icons.check_circle_outline_rounded,
                  Colors.green,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Still needs referral',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ...widget.unavailableVaccines.map(
                (vaccine) => _resultVaccineRow(
                  vaccine.vaccineName,
                  Icons.warning_amber_rounded,
                  Colors.orange,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create one referral for all remaining unavailable vaccines, '
                'or finish later. Uncompleted doses will remain visible in '
                'the child\'s schedule.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _AdministrationResultAction.finishLater,
            ),
            child: const Text('Finish later'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              _AdministrationResultAction.createReferral,
            ),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Create referral'),
          ),
        ],
      ),
    );
  }

  Widget _resultVaccineRow(String name, IconData icon, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 8),
        Expanded(child: Text(name)),
      ],
    ),
  );

  void _openChildProfile(ChildProfileSection section) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChildProfileScreen(
          child: widget.child,
          initialSection: section,
          repository: _vaccinationRepository,
        ),
      ),
    );
  }

  void _openReferral() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReferralScreen(
          child: widget.child,
          unavailableVaccines: widget.unavailableVaccines,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Vaccine Administration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CHILD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: primary.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: primary.withValues(alpha: 0.08),
                      child: Icon(
                        Icons.child_care_rounded,
                        color: primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.child.fullName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Child ID: ${widget.child.id}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Vaccines Ready',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 6),

              Text(
                'Confirm which available vaccines '
                'were administered during this visit.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              _clinicalScreeningCard(primary),

              const SizedBox(height: 18),

              ...widget.vaccines.map((vaccine) {
                final selected = _selectedVaccines.contains(vaccine.vaccineId);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? primary.withValues(alpha: 0.35)
                          : Colors.grey.withValues(alpha: 0.12),
                    ),
                  ),
                  child: CheckboxListTile(
                    value: selected,
                    activeColor: primary,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedVaccines.add(vaccine.vaccineId);
                        } else {
                          _selectedVaccines.remove(vaccine.vaccineId);
                        }
                      });
                    },
                    title: Text(
                      vaccine.vaccineName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${formatWholeNumber(vaccine.availableDoses)} doses available',
                    ),
                    secondary: Icon(
                      Icons.medical_services_outlined,
                      color: primary,
                    ),
                  ),
                );
              }),

              if (_selectedVaccines.length < widget.vaccines.length) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _notAdministeredReason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason not all recommended vaccines were given',
                    hintText:
                        'Clinical decision, guardian declined, or other reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // UNAVAILABLE VACCINES NOTICE
              if (widget.unavailableVaccines.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Referral Required',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.unavailableVaccines
                                  .map((vaccine) => vaccine.vaccineName)
                                  .join(', '),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Confirming saves the vaccination record, updates the child history and PNIP schedule, and deducts the administered dose from inventory.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving || _completed
                      ? null
                      : _confirmAdministration,
                  icon: Icon(
                    _completed
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline,
                  ),
                  label: Text(
                    _completed
                        ? 'Vaccination Recorded'
                        : _saving
                        ? 'Saving Vaccination...'
                        : 'Confirm Administration',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clinicalScreeningCard(Color primary) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: primary.withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Clinical Screening',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'PNIP determines schedule eligibility. A health worker must confirm clinical clearance before administration.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        _screeningCheck(
          'Vaccination card and system history reviewed',
          _historyReviewed,
          (value) => _historyReviewed = value,
        ),
        _screeningCheck(
          'Current condition and illness assessed',
          _conditionAssessed,
          (value) => _conditionAssessed = value,
        ),
        _screeningCheck(
          'Contraindications and previous reactions reviewed',
          _contraindicationsReviewed,
          (value) => _contraindicationsReviewed = value,
        ),
        _screeningCheck(
          'Guardian consent confirmed',
          _guardianConsentConfirmed,
          (value) => _guardianConsentConfirmed = value,
        ),
      ],
    ),
  );

  Widget _screeningCheck(String label, bool value, ValueChanged<bool> update) =>
      CheckboxListTile(
        value: value,
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label, style: const TextStyle(fontSize: 12.5)),
        onChanged: _saving || _completed
            ? null
            : (selected) => setState(() => update(selected ?? false)),
      );
}
