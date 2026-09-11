import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_relationship_options.dart';
import '../models/person_name.dart';
import '../repositories/child_repository.dart';
import '../utils/user_facing_error.dart';

class AddChildToGuardianScreen extends StatefulWidget {
  final GuardianProfile guardian;
  final String registeredByUserId;

  const AddChildToGuardianScreen({
    super.key,
    required this.guardian,
    required this.registeredByUserId,
  });

  @override
  State<AddChildToGuardianScreen> createState() =>
      _AddChildToGuardianScreenState();
}

class _AddChildToGuardianScreenState extends State<AddChildToGuardianScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameFieldKey = GlobalKey();
  final _lastNameFieldKey = GlobalKey();
  final _birthDateFieldKey = GlobalKey();
  final _authorizationFieldKey = GlobalKey();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _suffix = TextEditingController();
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  DateTime? _birthDate;
  String? _birthDateError;
  String? _authorizationError;
  String _sex = 'Female';
  late String _relationship;
  bool _authorizationConfirmed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _relationship = GuardianRelationshipOptions.defaultForSex(
      widget.guardian.sex,
    );
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _suffix.dispose();
    super.dispose();
  }

  String _formatDate(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: 'SELECT CHILD BIRTH DATE',
    );
    if (selected != null) {
      setState(() {
        _birthDate = selected;
        _birthDateError = null;
      });
    }
  }

  Future<void> _reviewAndSave() async {
    final formIsValid = _formKey.currentState!.validate();
    final firstMissingField = _firstName.text.trim().isEmpty
        ? _firstNameFieldKey
        : _lastName.text.trim().isEmpty
        ? _lastNameFieldKey
        : _birthDate == null
        ? _birthDateFieldKey
        : !_authorizationConfirmed
        ? _authorizationFieldKey
        : null;
    setState(() {
      _birthDateError = _birthDate == null
          ? 'Select the child’s birth date.'
          : null;
      _authorizationError = !_authorizationConfirmed
          ? 'Confirm the guardian’s authorization.'
          : null;
    });
    if (!formIsValid || firstMissingField != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final fieldContext = firstMissingField?.currentContext;
      if (fieldContext != null && fieldContext.mounted) {
        await Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
      }
      return;
    }
    final name = PersonName(
      firstName: _firstName.text,
      middleName: _middleName.text,
      lastName: _lastName.text,
      suffix: _suffix.text,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Review Child Link',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guardian: ${widget.guardian.fullName}'),
            Text('Guardian ID: ${widget.guardian.guardianCode}'),
            const Divider(height: 24),
            Text('Child: ${name.fullName}'),
            Text('Birth date: ${_formatDate(_birthDate!)}'),
            Text('Sex: $_sex'),
            Text('Relationship: $_relationship'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Back to edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm and save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final result = await _repository.addChildToExistingGuardian(
        ExistingGuardianChildRequest(
          guardianId: widget.guardian.id,
          child: ChildRegistrationInput.structured(
            name: name,
            birthDate: _birthDate!,
            sex: _sex,
            relationship: _relationship,
          ),
          authorizationConfirmed: true,
          registeredByUserId: widget.registeredByUserId,
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.child.fullName} added with ID ${result.child.id}.',
          ),
        ),
      );
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
                  'The child could not be added. Please review the information and try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add Child',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.family_restroom_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.guardian.fullName}\n${widget.guardian.guardianCode}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _nameField(
                      _firstName,
                      'First name',
                      true,
                      fieldKey: _firstNameFieldKey,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _nameField(
                      _lastName,
                      'Last name',
                      true,
                      fieldKey: _lastNameFieldKey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _nameField(
                      _middleName,
                      'Middle name or initial',
                      false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 105,
                    child: _nameField(_suffix, 'Suffix', false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                key: _birthDateFieldKey,
                onTap: _selectBirthDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Birth date',
                    suffixIcon: const Icon(Icons.calendar_month_rounded),
                    errorText: _birthDateError,
                  ),
                  child: Text(
                    _birthDate == null
                        ? 'Select date'
                        : _formatDate(_birthDate!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration: const InputDecoration(labelText: 'Sex'),
                items: const ['Female', 'Male']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _sex = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                decoration: const InputDecoration(
                  labelText: 'Relationship to guardian',
                ),
                items: GuardianRelationshipOptions.forSex(widget.guardian.sex)
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _relationship = value!),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: _authorizationFieldKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _authorizationConfirmed,
                onChanged: (value) => setState(() {
                  _authorizationConfirmed = value ?? false;
                  if (_authorizationConfirmed) _authorizationError = null;
                }),
                title: const Text('Guardian authorization confirmed'),
                subtitle: Text(
                  _authorizationError ??
                      'Required before linking another child to this guardian.',
                  style: _authorizationError == null
                      ? null
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _reviewAndSave,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_saving ? 'Saving...' : 'Review Child'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextFormField _nameField(
    TextEditingController controller,
    String label,
    bool required, {
    Key? fieldKey,
  }) => TextFormField(
    key: fieldKey,
    controller: controller,
    decoration: InputDecoration(labelText: label),
    textCapitalization: TextCapitalization.words,
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  );
}
