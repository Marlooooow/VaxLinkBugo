import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/guardian/guardian_correction.dart';
import '../models/guardian/guardian_profile.dart';
import '../models/guardian/guardian_relationship_options.dart';
import '../repositories/child_repository.dart';
import '../utils/user_facing_error.dart';
import '../models/person_name.dart';

class EditGuardianScreen extends StatefulWidget {
  final GuardianProfile guardian;
  final String correctedByUserId;

  const EditGuardianScreen({
    super.key,
    required this.guardian,
    required this.correctedByUserId,
  });

  @override
  State<EditGuardianScreen> createState() => _EditGuardianScreenState();
}

class _EditGuardianScreenState extends State<EditGuardianScreen> {
  final _formKey = GlobalKey<FormState>();
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _suffix;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  final _reason = TextEditingController();
  late bool _onlineAccessRequested;
  late String _sex;
  DateTime? _birthDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstName = TextEditingController(text: widget.guardian.firstName ?? '');
    _middleName = TextEditingController(text: widget.guardian.middleName ?? '');
    _lastName = TextEditingController(text: widget.guardian.lastName ?? '');
    _suffix = TextEditingController(text: widget.guardian.suffix ?? '');
    _phone = TextEditingController(text: widget.guardian.phoneNumber ?? '');
    _address = TextEditingController(text: widget.guardian.address);
    _sex = widget.guardian.sex;
    _birthDate = widget.guardian.birthDate;
    _onlineAccessRequested =
        widget.guardian.accessStatus ==
            GuardianAccessStatus.activeGuardianAccount ||
        widget.guardian.accessStatus == GuardianAccessStatus.invitationPending;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _suffix.dispose();
    _phone.dispose();
    _address.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final name = PersonName(
        firstName: _firstName.text,
        middleName: _middleName.text,
        lastName: _lastName.text,
        suffix: _suffix.text,
      );
      final result = await _repository.correctGuardian(
        GuardianCorrectionRequest(
          guardianId: widget.guardian.id,
          fullName: name.fullName,
          firstName: name.firstName,
          middleName: name.middleName,
          lastName: name.lastName,
          suffix: name.suffix,
          birthDate: _birthDate,
          sex: _sex,
          phoneNumber: _phone.text,
          address: _address.text,
          hasUserAccount: _onlineAccessRequested,
          reason: _reason.text,
          correctedByUserId: widget.correctedByUserId,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'The guardian correction could not be saved. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _selectBirthDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDate: _birthDate ?? DateTime(DateTime.now().year - 25),
    );
    if (selected != null) setState(() => _birthDate = selected);
  }

  String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Edit Guardian',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Text(
              widget.guardian.guardianCode,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _firstName, decoration: const InputDecoration(labelText: 'First name'), validator: _required)),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: _lastName, decoration: const InputDecoration(labelText: 'Last name'), validator: _required)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _middleName, decoration: const InputDecoration(labelText: 'Middle name or initial (optional)'))),
                const SizedBox(width: 10),
                SizedBox(width: 105, child: TextFormField(controller: _suffix, decoration: const InputDecoration(labelText: 'Suffix'))),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _selectBirthDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Guardian birth date', suffixIcon: Icon(Icons.calendar_month_rounded)),
                child: Text(_birthDate == null ? 'Select date' : _date(_birthDate!)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sex,
              decoration: const InputDecoration(labelText: 'Guardian sex'),
              items: GuardianRelationshipOptions.sexes
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _sex = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number (optional)',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            const SizedBox(height: 8),
            if (!RepositoryRegistry.instance.environment.isLive)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _onlineAccessRequested,
                onChanged: (value) =>
                    setState(() => _onlineAccessRequested = value),
                title: const Text('Online guardian access requested'),
                subtitle: const Text(
                  'A new request creates an invitation; it does not create a password.',
                ),
              ),
            if (RepositoryRegistry.instance.environment.isLive)
              const Text(
                'Online access is managed separately in the family details. Editing information does not change login access.',
              ),
            const Divider(height: 30),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason for correction',
                hintText: 'Example: Corrected guardian contact information',
                alignLabelWithHint: true,
              ),
              minLines: 3,
              maxLines: 4,
              validator: _required,
            ),
            const SizedBox(height: 8),
            Text(
              'The previous values, new values, health worker, and correction time will be retained.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Correction'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
