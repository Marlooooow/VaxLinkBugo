import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import '../models/child/child_correction.dart';
import '../models/guardian/guardian_relationship_options.dart';
import '../models/child/child_profile.dart';
import '../repositories/child_repository.dart';
import '../utils/user_facing_error.dart';

class EditChildScreen extends StatefulWidget {
  final ChildProfile child;
  final String? guardianId;
  final String? guardianSex;
  final String correctedByUserId;

  const EditChildScreen({
    super.key,
    required this.child,
    this.guardianId,
    this.guardianSex,
    required this.correctedByUserId,
  });

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  late final TextEditingController _name;
  final _reason = TextEditingController();
  late DateTime _birthDate;
  late String _sex;
  late String _relationship;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.child.fullName);
    _birthDate = widget.child.birthDate;
    _sex = widget.child.sex;
    _relationship = widget.child.relationship;
  }

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(now.year - 18),
      lastDate: now,
      helpText: 'CORRECT CHILD BIRTH DATE',
    );
    if (selected != null) setState(() => _birthDate = selected);
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result = await _repository.correctChild(
        ChildCorrectionRequest(
          childId: widget.child.id,
          guardianId: widget.guardianId,
          fullName: _name.text,
          birthDate: _birthDate,
          sex: _sex,
          relationship: _relationship,
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
                  'The child correction could not be saved. Please try again.',
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
        'Edit Child Information',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          Text(
            widget.child.id,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Child full name'),
            textCapitalization: TextCapitalization.words,
            validator: _required,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Birth date',
                suffixIcon: Icon(Icons.calendar_month_rounded),
              ),
              child: Text(_date(_birthDate)),
            ),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            decoration: const InputDecoration(
              labelText: 'Guardian’s relationship to child',
            ),
            items:
                GuardianRelationshipOptions.forSex(
                      widget.guardianSex ??
                          GuardianRelationshipOptions.sexForRelationship(
                            _relationship,
                          ),
                    )
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => _relationship = value!),
          ),
          const Divider(height: 30),
          TextFormField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason for correction',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 4,
            validator: _required,
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
