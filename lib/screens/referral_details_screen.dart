import 'package:flutter/material.dart';

import '../models/external_vaccination_record.dart';
import '../models/referral.dart';
import '../repositories/referral_repository.dart';
import '../repositories/demo_repository.dart';
import '../services/mock_identifier_generator.dart';
import '../utils/user_facing_error.dart';

class ReferralDetailsScreen extends StatefulWidget {
  final Referral referral;
  final ReferralRepository repository;

  const ReferralDetailsScreen({
    super.key,
    required this.referral,
    required this.repository,
  });

  @override
  State<ReferralDetailsScreen> createState() => _ReferralDetailsScreenState();
}

class _ReferralDetailsScreenState extends State<ReferralDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _facility = TextEditingController();
  final _healthWorker = TextEditingController();
  final _notes = TextEditingController();
  final _correctionReason = TextEditingController();
  late final TextEditingController _vaccine;
  late Referral _referral;
  DateTime? _dateAdministered;
  ExternalVaccinationRecord? _externalRecord;
  bool _verified = false;
  bool _saving = false;
  bool _loadingRecord = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _referral = widget.referral;
    _vaccine = TextEditingController(text: _referral.vaccineName);
    if (_referral.isCompleted) _loadExternalRecord();
  }

  Future<void> _loadExternalRecord() async {
    setState(() => _loadingRecord = true);
    final record = await widget.repository.getExternalVaccinationRecord(
      _referral.referralId,
    );
    if (!mounted) return;
    setState(() {
      _externalRecord = record;
      _loadingRecord = false;
    });
  }

  @override
  void dispose() {
    _vaccine.dispose();
    _facility.dispose();
    _healthWorker.dispose();
    _notes.dispose();
    _correctionReason.dispose();
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: _dateAdministered ?? now,
      firstDate: _referral.createdAt,
      lastDate: now,
      helpText: 'SELECT DATE ADMINISTERED',
    );
    if (result != null && mounted) setState(() => _dateAdministered = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateAdministered == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the date administered.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final useLocalIds = widget.repository is DemoRepository;
      final visitIdentity = _externalRecord == null && useLocalIds
          ? MockIdentifierGenerator.next(prefix: 'EV')
          : null;
      final recordIdentity = _externalRecord == null && useLocalIds
          ? MockIdentifierGenerator.next(prefix: 'VR')
          : null;
      final record = ExternalVaccinationRecord(
        recordId: _externalRecord?.recordId ?? recordIdentity?.id ?? '',
        recordCode: _externalRecord?.recordCode ?? recordIdentity?.code ?? '',
        referralId: _referral.referralId,
        externalVisitId:
            _externalRecord?.externalVisitId ?? visitIdentity?.id ?? '',
        externalVisitCode:
            _externalRecord?.externalVisitCode ?? visitIdentity?.code ?? '',
        childId: _referral.childId,
        vaccineId: _referral.vaccineId,
        vaccineAdministered: _vaccine.text.trim(),
        dateAdministered: _dateAdministered!,
        administeringFacility: _facility.text.trim(),
        healthWorkerName: _healthWorker.text.trim(),
        notes: _notes.text.trim(),
        recordedAt: now,
      );
      if (_editing) {
        final reason = _correctionReason.text.trim();
        if (reason.isEmpty) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a reason for the correction.')),
          );
          return;
        }
        final corrected = await widget.repository.updateExternalVaccination(
          record: record,
          correctionReason: reason,
        );
        if (!mounted) return;
        setState(() {
          _externalRecord = corrected;
          _editing = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vaccination record corrected.')),
        );
        return;
      }
      final updated = await widget.repository.recordExternalVaccination(
        referral: _referral,
        record: record,
      );
      if (!mounted) return;
      setState(() {
        _referral = updated;
        _externalRecord = record;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('External vaccination recorded.')),
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
                  'The external vaccination record could not be saved. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final completed = _referral.isCompleted;
    final statusColor = completed ? Colors.green : Colors.orange;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Referral Details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            children: [
              _StatusCard(referral: _referral, color: statusColor),
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Child Information',
                icon: Icons.child_care_rounded,
                color: primary,
                children: [
                  _InfoRow(label: 'Child', value: _referral.childName),
                  _InfoRow(label: 'Child ID', value: _referral.childId),
                ],
              ),
              const SizedBox(height: 14),
              _InfoCard(
                title: 'Vaccination Referral',
                icon: Icons.vaccines_outlined,
                color: primary,
                children: [
                  _InfoRow(label: 'Vaccine', value: _referral.vaccineName),
                  _InfoRow(label: 'Vaccine ID', value: _referral.vaccineId),
                  _InfoRow(label: 'Referral ID', value: _referral.referralId),
                  _InfoRow(label: 'Status', value: _referral.status),
                  _InfoRow(
                    label: 'Originating Facility',
                    value: _referral.originatingFacility,
                  ),
                  _InfoRow(label: 'Created', value: _date(_referral.createdAt)),
                  if (_referral.completedAt != null)
                    _InfoRow(
                      label: 'Completed',
                      value: _date(_referral.completedAt!),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (!completed && !_verified) ...[
                _VerificationNotice(color: primary),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _verified = true),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Signed Referral Verified'),
                  ),
                ),
              ],
              if (!completed && _verified) _recordForm(),
              if (completed && _editing) _recordForm(),
              if (completed && !_editing) ...[
                if (_loadingRecord)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (_externalRecord != null)
                  _externalRecordDetails(_externalRecord!, primary)
                else
                  const _RecordUnavailableNotice(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordForm() {
    return Form(
      key: _formKey,
      child: _InfoCard(
        title: _editing
            ? 'Correct External Vaccination'
            : 'Record External Vaccination',
        icon: Icons.post_add_rounded,
        color: Theme.of(context).colorScheme.primary,
        children: [
          TextFormField(
            controller: _vaccine,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Vaccine Administered',
              helperText: 'Verified from the referral QR',
              suffixIcon: Icon(Icons.lock_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date Administered',
                border: OutlineInputBorder(),
              ),
              child: Text(
                _dateAdministered == null
                    ? 'Select date'
                    : _date(_dateAdministered!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _entry(_facility, 'Administering Facility'),
          const SizedBox(height: 12),
          _entry(_healthWorker, 'Health Worker Name'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _correctionReason,
              validator: _required,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for Correction',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: Icon(
                _saving ? Icons.hourglass_top_rounded : Icons.save_outlined,
              ),
              label: Text(
                _saving
                    ? 'Saving...'
                    : _editing
                    ? 'Save Correction'
                    : 'Confirm and save',
              ),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _editing = false),
                child: const Text('Cancel Editing'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextFormField _entry(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      validator: _required,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _externalRecordDetails(
    ExternalVaccinationRecord record,
    Color primary,
  ) {
    final recordedTime = TimeOfDay.fromDateTime(
      record.recordedAt,
    ).format(context);
    return _InfoCard(
      title: 'External Vaccination Details',
      icon: Icons.health_and_safety_outlined,
      color: primary,
      trailing: TextButton.icon(
        onPressed: () => _startEditing(record),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.edit_outlined, size: 17),
        label: const Text('Edit'),
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record.vaccineAdministered,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _RecordedBadge(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Administered on ${_date(record.dateAdministered)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          label: 'Administering Facility',
          value: record.administeringFacility,
        ),
        _InfoRow(label: 'Health Worker', value: record.healthWorkerName),
        if (record.notes.isNotEmpty)
          _InfoRow(label: 'Notes', value: record.notes),
        _InfoRow(
          label: 'Encoded at Bugo',
          value: '${_date(record.recordedAt)} at $recordedTime',
        ),
        if (record.updatedAt != null) ...[
          _InfoRow(label: 'Last Corrected', value: _date(record.updatedAt!)),
          if (record.correctionReason != null)
            _InfoRow(
              label: 'Correction Reason',
              value: record.correctionReason!,
            ),
        ],
        const Divider(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Completed referrals cannot be recorded again.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _startEditing(ExternalVaccinationRecord record) {
    _vaccine.text = record.vaccineAdministered;
    _facility.text = record.administeringFacility;
    _healthWorker.text = record.healthWorkerName;
    _notes.text = record.notes;
    _correctionReason.clear();
    setState(() {
      _dateAdministered = record.dateAdministered;
      _editing = true;
    });
  }
}

class _StatusCard extends StatelessWidget {
  final Referral referral;
  final Color color;
  const _StatusCard({required this.referral, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Column(
      children: [
        Icon(
          referral.isCompleted
              ? Icons.check_circle_outline
              : Icons.assignment_late_outlined,
          color: color,
          size: 48,
        ),
        const SizedBox(height: 10),
        const Text(
          'Vaccination Referral',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        Text(
          referral.status,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _VerificationNotice extends StatelessWidget {
  final Color color;
  const _VerificationNotice({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Compare the signed referral with the child vaccination card. Continue only when the child, vaccine, facility, date, health worker, signature, and stamp are valid.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _RecordUnavailableNotice extends StatelessWidget {
  const _RecordUnavailableNotice();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: Colors.orange),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'This referral is marked completed, but its external vaccination details are not available in the current app session.',
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final List<Widget> children;
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.color,
    this.trailing,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

class _RecordedBadge extends StatelessWidget {
  const _RecordedBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.green.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
        SizedBox(width: 4),
        Text(
          'Recorded',
          style: TextStyle(
            color: Colors.green,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 125,
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
