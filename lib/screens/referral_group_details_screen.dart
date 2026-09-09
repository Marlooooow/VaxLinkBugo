import 'package:flutter/material.dart';

import '../models/external_vaccination/external_vaccination_record.dart';
import '../models/external_vaccination/external_vaccination_visit.dart';
import '../models/referral.dart';
import '../models/referral_verification_result.dart';
import '../repositories/referral_repository.dart';
import '../services/mock_identifier_generator.dart';
import '../utils/user_facing_error.dart';
import 'referral_details_screen.dart';
import '../widgets/app_loading.dart';

class ReferralGroupDetailsScreen extends StatefulWidget {
  final List<Referral> referrals;
  final ReferralRepository repository;

  const ReferralGroupDetailsScreen({
    super.key,
    required this.referrals,
    required this.repository,
  });

  @override
  State<ReferralGroupDetailsScreen> createState() =>
      _ReferralGroupDetailsScreenState();
}

class _ReferralGroupDetailsScreenState
    extends State<ReferralGroupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _facility = TextEditingController();
  final _worker = TextEditingController();
  final _notes = TextEditingController();
  late List<Referral> _referrals;
  final Set<String> _selectedIds = {};
  final Map<String, ExternalVaccinationVisit> _visits = {};
  DateTime? _dateAdministered;
  bool _verified = false;
  bool _saving = false;
  bool _selectingVisit = false;
  bool _checkingReferral = true;
  bool _referralConfirmed = false;
  bool _documentVerified = false;
  ReferralVerificationResult? _verificationResult;
  String? _expandedReferralId;

  @override
  void initState() {
    super.initState();
    _referrals = List.of(widget.referrals);
    _loadVisits();
    _verifyReferral();
  }

  Future<void> _verifyReferral() async {
    final result = await widget.repository.verifyReferralGroup(
      referralGroupId: _referrals.first.referralGroupId,
    );
    if (!mounted) return;
    setState(() {
      _verificationResult = result;
      _checkingReferral = false;
    });
  }

  Future<void> _loadVisits() async {
    final visits = <String, ExternalVaccinationVisit>{};
    for (final referral in _referrals.where((item) => item.isCompleted)) {
      final visit = await widget.repository
          .getExternalVaccinationVisitByReferralId(referral.referralId);
      if (visit != null) visits[visit.externalVisitId] = visit;
    }
    if (!mounted) return;
    setState(() {
      _visits
        ..clear()
        ..addAll(visits);
    });
  }

  @override
  void dispose() {
    _facility.dispose();
    _worker.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _date(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  DateTime get _referralIssuedAt => _referrals
      .map((item) => item.createdAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateAdministered ?? now,
      firstDate: _referralIssuedAt,
      lastDate: now,
      helpText: 'SELECT DATE ADMINISTERED',
    );
    if (selected != null && mounted) {
      setState(() => _dateAdministered = selected);
    }
  }

  Future<void> _save() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one administered vaccine.'),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_dateAdministered == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the date administered.')),
      );
      return;
    }
    final selected = _referrals
        .where(
          (item) => _selectedIds.contains(item.referralId) && item.isPending,
        )
        .toList();
    if (selected.isEmpty) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final visitIdentity = MockIdentifierGenerator.next(prefix: 'EV');
      final records = selected.map((referral) {
        final recordIdentity = MockIdentifierGenerator.next(prefix: 'VR');
        return ExternalVaccinationRecord(
          recordId: recordIdentity.id,
          recordCode: recordIdentity.code,
          referralId: referral.referralId,
          externalVisitId: visitIdentity.id,
          externalVisitCode: visitIdentity.code,
          childId: referral.childId,
          vaccineId: referral.vaccineId,
          vaccineAdministered: referral.vaccineName,
          dateAdministered: _dateAdministered!,
          administeringFacility: _facility.text.trim(),
          healthWorkerName: _worker.text.trim(),
          notes: _notes.text.trim(),
          recordedAt: now,
        );
      }).toList();
      final completed = await widget.repository.recordExternalVaccinationBatch(
        referrals: selected,
        records: records,
      );
      if (!mounted) return;
      final completedById = {
        for (final item in completed) item.referralId: item,
      };
      setState(() {
        _referrals = _referrals
            .map((item) => completedById[item.referralId] ?? item)
            .toList();
        _selectedIds.clear();
        _verified = false;
        _selectingVisit = false;
        _documentVerified = false;
        _saving = false;
      });
      await _loadVisits();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${completed.length} vaccination(s) recorded.')),
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
                  'The external vaccination visit could not be saved. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _reviewVisit() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one vaccine.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_dateAdministered == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the date administered.')),
      );
      return;
    }
    if (!_documentVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm that the signed referral was verified.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Review External Visit',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Confirm these details match the signed referral.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              _reviewRow(
                'Vaccines',
                _referrals
                    .where((item) => _selectedIds.contains(item.referralId))
                    .map((item) => item.vaccineName)
                    .join(', '),
              ),
              _reviewRow('Date Administered', _date(_dateAdministered!)),
              _reviewRow('Facility', _facility.text.trim()),
              _reviewRow('Health Worker', _worker.text.trim()),
              if (_notes.text.trim().isNotEmpty)
                _reviewRow('Notes', _notes.text.trim()),
              const Divider(height: 24),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_outlined, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Signed printed referral verified.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Saving will mark the selected vaccine referral(s) as completed.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to edit'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Confirm and save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final pending = _referrals.where((item) => item.isPending).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Referral Details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: _checkingReferral
            ? const AppLoadingView(
                title: 'Checking referral',
                message: 'Verifying the referral and vaccination records.',
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_referralConfirmed) ...[
                      _referralVerificationPanel(primary),
                    ] else ...[
                      Text(
                        _referrals.first.childName,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Child ID: ${_referrals.first.childId}  •  ${_referrals.first.referralGroupCode}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Referred Vaccines',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Review the referral status and record each external visit separately.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._referrals.map(
                        (referral) => _vaccineTile(referral, primary),
                      ),
                      if (pending.isNotEmpty &&
                          !_selectingVisit &&
                          !_verified) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                setState(() => _selectingVisit = true),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Record External Visit'),
                          ),
                        ),
                      ],
                      if (pending.isNotEmpty &&
                          _selectingVisit &&
                          !_verified) ...[
                        const SizedBox(height: 16),
                        _visitSelectionPanel(pending, primary),
                      ],
                      if (pending.isNotEmpty && _verified) ...[
                        const SizedBox(height: 18),
                        _recordForm(primary),
                      ],
                      if (pending.isEmpty) ...[
                        const SizedBox(height: 16),
                        _completedSummary(primary),
                      ],
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _referralVerificationPanel(Color primary) {
    final result = _verificationResult;
    final canContinue = result?.canContinue ?? false;
    final isCompleted = result?.status == ReferralVerificationStatus.completed;
    final isPartiallyCompleted =
        !isCompleted &&
        _referrals.any((item) => item.isCompleted) &&
        _referrals.any((item) => item.isPending);
    final isInvalid =
        result?.status == ReferralVerificationStatus.notFound ||
        result?.status == ReferralVerificationStatus.invalidToken ||
        result?.status == ReferralVerificationStatus.cancelled;
    final statusColor = isCompleted
        ? Colors.green
        : isInvalid
        ? Colors.red
        : isPartiallyCompleted
        ? Colors.orange
        : Colors.blue;
    final statusIcon = isCompleted
        ? Icons.check_circle_outline_rounded
        : isInvalid
        ? Icons.error_outline_rounded
        : isPartiallyCompleted
        ? Icons.info_outline_rounded
        : Icons.verified_outlined;
    final statusTitle = isCompleted
        ? 'Referral Completed'
        : isInvalid
        ? 'Referral Verification Failed'
        : isPartiallyCompleted
        ? 'Referral Partially Completed'
        : 'Referral Verified';
    final first = _referrals.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.20)),
          ),
          child: Column(
            children: [
              Icon(statusIcon, color: statusColor, size: 38),
              const SizedBox(height: 10),
              Text(
                statusTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                result?.message ?? 'Unable to verify this referral.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Confirm Referral Details',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              _visitRow('Child', first.childName),
              _visitRow('Child ID', first.childId),
              _visitRow('Referral Group', first.referralGroupCode),
              _visitRow('Originating Facility', first.originatingFacility),
              _visitRow('Date Issued', _date(_referralIssuedAt)),
              _visitRow(
                'Referred Vaccines',
                _referrals.map((item) => item.vaccineName).join(', '),
              ),
              _visitRow(
                'Current Status',
                isCompleted
                    ? 'Completed'
                    : _referrals.any((item) => item.isCompleted)
                    ? 'Partially completed'
                    : 'Pending',
              ),
              const Divider(height: 26),
              const Text(
                'Vaccine Referrals',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ..._referrals.map(_verificationVaccineCard),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canContinue || isCompleted
                    ? () => setState(() => _referralConfirmed = true)
                    : null,
                icon: Icon(
                  isCompleted
                      ? Icons.visibility_outlined
                      : Icons.arrow_forward_rounded,
                ),
                label: Text(isCompleted ? 'View Recorded Details' : 'Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _verificationVaccineCard(Referral referral) {
    final visit = _visitForReferral(referral.referralId);
    final statusColor = referral.isCompleted ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  referral.vaccineName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _statusBadge(referral.status, statusColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            referral.referralId,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 8),
          _compactDetail('Dose', 'Dose ${referral.doseNumber}'),
          _compactDetail('PNIP Due', _date(referral.scheduledDueDate)),
          if (visit != null) ...[
            const SizedBox(height: 10),
            _compactDetail('Administered', _date(visit.dateAdministered)),
            _compactDetail('Facility', visit.administeringFacility),
            _compactDetail('Health Worker', visit.healthWorkerName),
            _compactDetail(
              'Signed Referral',
              visit.documentVerified ? 'Verified' : 'Not verified',
            ),
            _compactDetail('Encoded', _date(visit.recordedAt)),
          ],
        ],
      ),
    );
  }

  Widget _compactDetail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _vaccineTile(Referral referral, Color primary) {
    final expanded = _expandedReferralId == referral.referralId;
    final visit = _visitForReferral(referral.referralId);
    final statusColor = referral.isCompleted ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: expanded
              ? primary.withValues(alpha: 0.25)
              : Colors.grey.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _expandedReferralId = expanded ? null : referral.referralId;
            }),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Icon(Icons.vaccines_outlined, color: primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          referral.vaccineName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          referral.referralId,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(referral.status, statusColor),
                  const SizedBox(width: 5),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: referral.isCompleted && visit != null
                  ? _completedVaccineDetails(referral, visit)
                  : _pendingVaccineDetails(referral),
            ),
          ],
        ],
      ),
    );
  }

  ExternalVaccinationVisit? _visitForReferral(String referralId) {
    for (final visit in _visits.values) {
      if (visit.records.any((record) => record.referralId == referralId)) {
        return visit;
      }
    }
    return null;
  }

  Widget _pendingVaccineDetails(Referral referral) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _visitRow('Referral Issued', _date(referral.createdAt)),
      _visitRow('Vaccine Dose', 'Dose ${referral.doseNumber}'),
      _visitRow('PNIP Due Date', _date(referral.scheduledDueDate)),
      _visitRow('Originating Facility', referral.originatingFacility),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No external vaccination has been recorded for this referral.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
      ),
    ],
  );

  Widget _completedVaccineDetails(
    Referral referral,
    ExternalVaccinationVisit visit,
  ) {
    final time = TimeOfDay.fromDateTime(visit.recordedAt).format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _visitRow('Date Administered', _date(visit.dateAdministered)),
        _visitRow('Administering Facility', visit.administeringFacility),
        _visitRow('Health Worker', visit.healthWorkerName),
        if (visit.notes.isNotEmpty) _visitRow('Notes', visit.notes),
        _visitRow('Encoded at Bugo', '${_date(visit.recordedAt)} at $time'),
        if (visit.records.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 6),
            child: Text(
              'Same external visit as ${visit.records.where((record) => record.referralId != referral.referralId).map((record) => record.vaccineAdministered).join(', ')}.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _openVisitForCorrection(visit),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Review or Correct'),
          ),
        ),
      ],
    );
  }

  Widget _visitSelectionPanel(List<Referral> pending, Color primary) {
    final allSelected =
        pending.isNotEmpty &&
        pending.every((item) => _selectedIds.contains(item.referralId));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vaccines from this visit',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Select vaccines confirmed on the same signed external visit.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (pending.length > 1) ...[
            const SizedBox(height: 10),
            CheckboxListTile(
              value: allSelected,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Select all vaccines from the same visit',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Use only when facility, date, and health worker are the same.',
              ),
              onChanged: (value) => setState(() {
                _selectedIds.clear();
                if (value ?? false) {
                  _selectedIds.addAll(pending.map((item) => item.referralId));
                }
              }),
            ),
            const Divider(),
          ],
          ...pending.map(
            (referral) => CheckboxListTile(
              value: _selectedIds.contains(referral.referralId),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                referral.vaccineName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(referral.referralId),
              onChanged: (value) => setState(() {
                if (value ?? false) {
                  _selectedIds.add(referral.referralId);
                } else {
                  _selectedIds.remove(referral.referralId);
                }
              }),
            ),
          ),
          if (_selectedIds.length > 1)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Multiple vaccines will share one date, facility, health worker, and notes.',
                style: TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _selectedIds.clear();
                    _selectingVisit = false;
                  }),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => setState(() => _verified = true),
                  child: const Text('Verify Visit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recordForm(Color primary) => Form(
    key: _formKey,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record External Visit',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            '${_selectedIds.length} vaccine${_selectedIds.length == 1 ? '' : 's'} selected',
            style: TextStyle(
              color: primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Vaccines Administered',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.lock_outline_rounded),
            ),
            child: Text(
              _referrals
                  .where((item) => _selectedIds.contains(item.referralId))
                  .map((item) => item.vaccineName)
                  .join(', '),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Referral Issued',
              helperText: 'Fixed by the original referral',
              suffixIcon: Icon(Icons.lock_outline_rounded),
              border: OutlineInputBorder(),
            ),
            child: Text(_date(_referralIssuedAt)),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date Administered',
                helperText:
                    'Select from ${_date(_referralIssuedAt)} through today',
                border: const OutlineInputBorder(),
              ),
              child: Text(
                _dateAdministered == null
                    ? 'Select date'
                    : _date(_dateAdministered!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _field(_facility, 'Administering Facility'),
          const SizedBox(height: 12),
          _field(_worker, 'Health Worker Name'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _documentVerified,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I verified the signed referral presented by the guardian.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Required before this external vaccination can be saved.',
            ),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _documentVerified = value ?? false;
                  }),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _verified = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to Selection'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _reviewVisit,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(_saving ? 'Saving...' : 'Review Visit'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  TextFormField _field(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        validator: _required,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _completedSummary(Color primary) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All referred vaccines recorded',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text('No referred vaccines remain pending.'),
      ],
    ),
  );

  Widget _statusBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _visitRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 135,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Future<void> _openVisitForCorrection(ExternalVaccinationVisit visit) async {
    final referralId = visit.records.first.referralId;
    final referral = _referrals.firstWhere(
      (item) => item.referralId == referralId,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReferralDetailsScreen(
          referral: referral,
          repository: widget.repository,
        ),
      ),
    );
    await _loadVisits();
  }
}
