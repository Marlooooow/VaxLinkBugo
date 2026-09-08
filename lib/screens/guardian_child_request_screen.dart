import 'package:flutter/material.dart';

import '../models/child/child_link_request.dart';
import '../utils/user_facing_error.dart';
import '../models/guardian/guardian_relationship_options.dart';
import '../models/person_name.dart';
import '../repositories/child_repository.dart';

class GuardianChildRequestScreen extends StatefulWidget {
  final String guardianUserId;
  final ChildRepository repository;

  const GuardianChildRequestScreen({
    super.key,
    required this.guardianUserId,
    required this.repository,
  });

  @override
  State<GuardianChildRequestScreen> createState() =>
      _GuardianChildRequestScreenState();
}

class _GuardianChildRequestScreenState
    extends State<GuardianChildRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _suffix = TextEditingController();
  DateTime? _birthDate;
  String _sex = 'Female';
  String _guardianSex = 'Female';
  String _relationship = 'Mother';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadGuardianSex();
  }

  Future<void> _loadGuardianSex() async {
    final guardian = await widget.repository.findGuardianById(
      widget.guardianUserId,
    );
    if (!mounted || guardian == null) return;
    setState(() {
      _guardianSex = guardian.sex;
      _relationship = GuardianRelationshipOptions.defaultForSex(guardian.sex);
    });
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _suffix.dispose();
    super.dispose();
  }

  Future<void> _selectBirthDate() async {
    final today = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime(today.year - 1, today.month, today.day),
      firstDate: DateTime(2008),
      lastDate: today,
    );
    if (result != null) setState(() => _birthDate = result);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the child birth date.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await widget.repository.submitChildLinkRequest(
        SubmitChildLinkRequest.structured(
          guardianUserId: widget.guardianUserId,
          childName: PersonName(
            firstName: _firstName.text,
            middleName: _middleName.text,
            lastName: _lastName.text,
            suffix: _suffix.text,
          ),
          birthDate: _birthDate!,
          sex: _sex,
          relationship: _relationship,
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
                  'The child-link request could not be submitted. Please try again.',
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
        'Request to Add Child',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'The child will appear in your account after a health worker verifies the identity and guardian relationship.',
                    style: TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _nameField(_firstName, 'First name', true)),
              const SizedBox(width: 10),
              Expanded(child: _nameField(_lastName, 'Last name', true)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _nameField(_middleName, 'Middle name or initial', false),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 105, child: _nameField(_suffix, 'Suffix', false)),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _selectBirthDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Birth date',
                suffixIcon: Icon(Icons.calendar_month_outlined),
              ),
              child: Text(
                _birthDate == null
                    ? 'Select date'
                    : '${_birthDate!.month.toString().padLeft(2, '0')}/${_birthDate!.day.toString().padLeft(2, '0')}/${_birthDate!.year}',
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: const ['Female', 'Male']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _sex = value!),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey(_guardianSex),
            initialValue: _relationship,
            decoration: const InputDecoration(labelText: 'Your relationship'),
            items: GuardianRelationshipOptions.forSex(_guardianSex)
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _relationship = value!),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Submit for Verification'),
          ),
        ],
      ),
    ),
  );

  TextFormField _nameField(
    TextEditingController controller,
    String label,
    bool required,
  ) => TextFormField(
    controller: controller,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(labelText: label),
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  );
}
