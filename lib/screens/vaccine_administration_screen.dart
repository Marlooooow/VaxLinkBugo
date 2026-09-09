import 'package:flutter/material.dart';

import '../models/child/child_profile.dart';
import '../models/vaccine_inventory.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../repositories/repository_registry.dart';
import '../utils/number_formatter.dart';
import '../utils/user_facing_error.dart';
import '../repositories/vaccination_repository.dart';
import '../services/mock_identifier_generator.dart';
import 'referral_screen.dart';
import 'child_profile_screen.dart';

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
      final screeningIdentity = MockIdentifierGenerator.next(prefix: 'SCR');
      var screening = VaccinationScreening(
        id: screeningIdentity.id,
        screeningCode: screeningIdentity.code,
        childId: widget.child.id,
        historyReviewed: _historyReviewed,
        currentConditionAssessed: _conditionAssessed,
        contraindicationsReviewed: _contraindicationsReviewed,
        guardianConsentConfirmed: _guardianConsentConfirmed,
        outcome: VaccinationScreeningOutcome.cleared,
        notes: _notAdministeredReason.text.trim(),
        screenedAt: now,
        screenedByUserId: '00000000-0000-4000-8000-000000000201',
      );
      final selectedInventory = widget.vaccines
          .where((item) => _selectedVaccines.contains(item.vaccineId))
          .toList();
      final records = selectedInventory.map((vaccine) {
        final scheduledDose = assessment.recommendedDoses.firstWhere(
          (dose) => dose.vaccineId == vaccine.vaccineId,
        );
        final identity = MockIdentifierGenerator.next(prefix: 'VAX');
        return VaccinationRecord(
          id: identity.id,
          recordCode: identity.code,
          childId: widget.child.id,
          vaccineId: vaccine.vaccineId,
          vaccineName: vaccine.vaccineName,
          doseNumber: scheduledDose.doseNumber,
          dateAdministered: now,
          administeringFacility: 'Barangay Bugo Health Center',
          healthWorkerName: 'Bugo Health Worker',
          healthWorkerId: '00000000-0000-4000-8000-000000000201',
          source: VaccinationSource.bugo,
          notes: 'Recorded through the normal vaccination workflow.',
          recordedAt: now,
          recordedByUserId: '00000000-0000-4000-8000-000000000201',
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
      final viewedProfile = await _showAdministrationSuccessDialog(records.length);
      if (viewedProfile) return;
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

    if (widget.unavailableVaccines.isEmpty) {
      return;
    }

    // There are still vaccines that could not be administered at this
    // facility. Show the referral option after confirming the successful save.
    if (mounted) _showReferralRequiredDialog();
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

  void _showReferralRequiredDialog() {
    final unavailableCount = widget.unavailableVaccines.length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Referral Required',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            '$unavailableCount vaccine'
            '${unavailableCount > 1 ? 's are' : ' is'} '
            'still unavailable at this facility.\n\n'
            'A referral can now be generated for '
            'the remaining vaccine'
            '${unavailableCount > 1 ? 's' : ''}.',
          ),
          actionsAlignment: MainAxisAlignment.end,
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Later'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);

                _openReferral();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Create Referral'),
            ),
          ],
        );
      },
    );
  }

  void _openReferral() {
    Navigator.push(
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
