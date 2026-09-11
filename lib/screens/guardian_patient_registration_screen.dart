import '../repositories/repository_registry.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import '../utils/user_facing_error.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_relationship_options.dart';
import '../models/person_name.dart';
import '../repositories/child_repository.dart';
import '../widgets/worker_app_bar_actions.dart';
import 'vaccination_assessment_screen.dart';

class GuardianPatientRegistrationScreen extends StatefulWidget {
  final AppUser healthWorker;

  const GuardianPatientRegistrationScreen({
    super.key,
    required this.healthWorker,
  });

  @override
  State<GuardianPatientRegistrationScreen> createState() =>
      _GuardianPatientRegistrationScreenState();
}

class _GuardianPatientRegistrationScreenState
    extends State<GuardianPatientRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guardianFirstNameFieldKey = GlobalKey();
  final _guardianLastNameFieldKey = GlobalKey();
  final _guardianBirthDateFieldKey = GlobalKey();
  final _phoneFieldKey = GlobalKey();
  final _emailFieldKey = GlobalKey();
  final _addressFieldKey = GlobalKey();
  final _childFirstNameFieldKey = GlobalKey();
  final _childLastNameFieldKey = GlobalKey();
  final _childBirthDateFieldKey = GlobalKey();
  final _authorizationFieldKey = GlobalKey();
  final ChildRepository _repository =
      RepositoryRegistry.instance.childRepository;
  final _guardianFirstName = TextEditingController();
  final _guardianMiddleName = TextEditingController();
  final _guardianLastName = TextEditingController();
  final _guardianSuffix = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _childFirstName = TextEditingController();
  final _childMiddleName = TextEditingController();
  final _childLastName = TextEditingController();
  final _childSuffix = TextEditingController();
  DateTime? _guardianBirthDate;
  DateTime? _birthDate;
  String? _guardianBirthDateError;
  String? _birthDateError;
  String? _phoneError;
  String? _emailError;
  String? _authorizationError;
  String _guardianSex = 'Female';
  String _sex = 'Female';
  String _relationship = 'Mother';
  bool _createAccount = false;
  late GuardianInvitationChannel _invitationChannel =
      RepositoryRegistry.instance.environment.isLive
      ? GuardianInvitationChannel.printedSlip
      : GuardianInvitationChannel.sms;
  bool _authorizationConfirmed = false;
  bool _saving = false;
  final List<ChildRegistrationInput> _additionalChildren = [];

  @override
  void dispose() {
    _guardianFirstName.dispose();
    _guardianMiddleName.dispose();
    _guardianLastName.dispose();
    _guardianSuffix.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _childFirstName.dispose();
    _childMiddleName.dispose();
    _childLastName.dispose();
    _childSuffix.dispose();
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

  Future<void> _selectGuardianBirthDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _guardianBirthDate ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'SELECT GUARDIAN BIRTH DATE',
    );
    if (selected != null) {
      setState(() {
        _guardianBirthDate = selected;
        _guardianBirthDateError = null;
      });
    }
  }

  PersonName get _guardianStructuredName => PersonName(
    firstName: _guardianFirstName.text,
    middleName: _guardianMiddleName.text,
    lastName: _guardianLastName.text,
    suffix: _guardianSuffix.text,
  );

  PersonName get _childStructuredName => PersonName(
    firstName: _childFirstName.text,
    middleName: _childMiddleName.text,
    lastName: _childLastName.text,
    suffix: _childSuffix.text,
  );

  GlobalKey? _firstMissingRequiredField() {
    if (_guardianFirstName.text.trim().isEmpty) {
      return _guardianFirstNameFieldKey;
    }
    if (_guardianLastName.text.trim().isEmpty) {
      return _guardianLastNameFieldKey;
    }
    if (_guardianBirthDate == null) return _guardianBirthDateFieldKey;
    if (_createAccount &&
        _invitationChannel == GuardianInvitationChannel.sms &&
        _phone.text.trim().isEmpty) {
      return _phoneFieldKey;
    }
    if (_createAccount &&
        _invitationChannel == GuardianInvitationChannel.email &&
        _email.text.trim().isEmpty) {
      return _emailFieldKey;
    }
    if (_address.text.trim().isEmpty) return _addressFieldKey;
    if (_childFirstName.text.trim().isEmpty) {
      return _childFirstNameFieldKey;
    }
    if (_childLastName.text.trim().isEmpty) return _childLastNameFieldKey;
    if (_birthDate == null) return _childBirthDateFieldKey;
    if (!_authorizationConfirmed) return _authorizationFieldKey;
    return null;
  }

  Future<void> _scrollToField(GlobalKey fieldKey) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final fieldContext = fieldKey.currentContext;
    if (fieldContext == null || !fieldContext.mounted) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  Future<void> _review() async {
    final formIsValid = _formKey.currentState!.validate();
    final firstMissingField = _firstMissingRequiredField();
    setState(() {
      _birthDateError = _birthDate == null
          ? 'Select the child’s birth date.'
          : null;
      _guardianBirthDateError = _guardianBirthDate == null
          ? 'Select the guardian’s birth date.'
          : null;
      _phoneError =
          _createAccount &&
              _invitationChannel == GuardianInvitationChannel.sms &&
              _phone.text.trim().isEmpty
          ? 'Enter the guardian’s mobile number for the invitation.'
          : null;
      _emailError =
          _createAccount &&
              _invitationChannel == GuardianInvitationChannel.email &&
              _email.text.trim().isEmpty
          ? 'Enter the guardian’s email address for the invitation.'
          : null;
      _authorizationError = !_authorizationConfirmed
          ? 'Confirm the guardian’s identity and authority.'
          : null;
    });
    if (!formIsValid || firstMissingField != null) {
      if (firstMissingField != null) {
        await _scrollToField(firstMissingField);
      }
      return;
    }
    final children = _childrenForSubmission();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Review Registration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewRow(
              label: 'Guardian',
              value: _guardianStructuredName.fullName,
            ),
            _ReviewRow(
              label: 'Guardian birth date',
              value: _date(_guardianBirthDate!),
            ),
            _ReviewRow(label: 'Guardian sex', value: _guardianSex),
            _ReviewRow(
              label: 'Access',
              value: _createAccount
                  ? 'Online access — invitation pending'
                  : 'Health-worker managed',
            ),
            if (_createAccount)
              _ReviewRow(
                label: 'Invitation',
                value: switch (_invitationChannel) {
                  GuardianInvitationChannel.sms => 'SMS',
                  GuardianInvitationChannel.email => 'Email',
                  GuardianInvitationChannel.printedSlip => 'Printed slip',
                },
              ),
            _ReviewRow(
              label: 'Children (${children.length})',
              value: children
                  .map((child) => '${child.fullName} • ${child.relationship}')
                  .join('\n'),
            ),
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
    if (confirmed == true) await _save(children);
  }

  List<ChildRegistrationInput> _childrenForSubmission() => [
    ..._additionalChildren,
    ChildRegistrationInput.structured(
      name: _childStructuredName,
      birthDate: _birthDate!,
      sex: _sex,
      relationship: _relationship,
    ),
  ];

  void _addAnotherChild() {
    if (_childFirstName.text.trim().isEmpty ||
        _childLastName.text.trim().isEmpty ||
        _birthDate == null) {
      if (_birthDate == null) {
        setState(() {
          _birthDateError = 'Select the child’s birth date.';
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete the current child first.')),
      );
      return;
    }
    setState(() {
      _additionalChildren.add(
        ChildRegistrationInput.structured(
          name: _childStructuredName,
          birthDate: _birthDate!,
          sex: _sex,
          relationship: _relationship,
        ),
      );
      _childFirstName.clear();
      _childMiddleName.clear();
      _childLastName.clear();
      _childSuffix.clear();
      _birthDate = null;
      _birthDateError = null;
      _sex = 'Female';
      _relationship = GuardianRelationshipOptions.defaultForSex(_guardianSex);
    });
  }

  Future<void> _save(List<ChildRegistrationInput> children) async {
    setState(() => _saving = true);
    try {
      final result = await _repository.registerGuardianAndChild(
        GuardianRegistrationRequest.structured(
          guardianName: _guardianStructuredName,
          guardianBirthDate: _guardianBirthDate!,
          guardianSex: _guardianSex,
          phoneNumber: _phone.text,
          emailAddress: _email.text,
          address: _address.text,
          createUserAccount: _createAccount,
          invitationChannel: _createAccount ? _invitationChannel : null,
          children: children,
          authorizationConfirmed: _authorizationConfirmed,
          registeredByUserId: widget.healthWorker.id,
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final continueToAssessment = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
            size: 42,
          ),
          title: const Text('Registration Complete'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${result.children.length} child record(s) are now linked to ${result.guardian.fullName}.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                'Child IDs: ${result.children.map((child) => child.qrIdentifier).join(', ')}\nGuardian ID: ${result.guardian.guardianCode}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                result.guardian.accessStatus ==
                        GuardianAccessStatus.invitationPending
                    ? 'Online access invitation prepared. The guardian creates their own password during activation.'
                    : 'This record will be managed by authorized health workers.',
                textAlign: TextAlign.center,
              ),
              if (result.guardian.invitationCode != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  'Activation code: ${result.guardian.invitationCode}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (result.invitation != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    result.invitation!.channel ==
                            GuardianInvitationChannel.printedSlip
                        ? 'Give this code privately to the guardian. It is shown once and expires in 7 days.'
                        : result.invitation!.status ==
                              GuardianInvitationStatus.delivered
                        ? 'The activation instructions were sent to ${result.invitation!.maskedDestination}.'
                        : 'The SMS could not be sent. Give or print the activation code instead.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ],
          ),
          actions: [
            if (result.guardian.invitationCode != null &&
                result.invitation != null)
              TextButton.icon(
                onPressed: () => _printActivationSlip(result),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print Activation Slip'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Done for Now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('First Visit Assessment'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (continueToAssessment == true) {
        var child = result.children.first;
        if (result.children.length > 1) {
          final selected = await showDialog<int>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: const Text('Select child for assessment'),
              children: [
                for (var index = 0; index < result.children.length; index++)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, index),
                    child: ListTile(
                      leading: const Icon(Icons.child_care_rounded),
                      title: Text(result.children[index].fullName),
                      subtitle: Text(result.children[index].qrIdentifier),
                    ),
                  ),
              ],
            ),
          );
          if (selected == null || !mounted) return;
          child = result.children[selected];
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VaccinationAssessmentScreen(child: child),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback:
                  'We could not confirm the registration. Check Registered Families before submitting again.',
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
          'Guardian & Child Registration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: const [WorkerAppBarActions()],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            child: Column(
              children: [
                const _IntroCard(),
                const SizedBox(height: 18),
                const _SectionTitle(
                  icon: Icons.person_outline_rounded,
                  title: 'Guardian Information',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: _guardianFirstNameFieldKey,
                        controller: _guardianFirstName,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: _guardianLastNameFieldKey,
                        controller: _guardianLastName,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _guardianMiddleName,
                        decoration: const InputDecoration(
                          labelText: 'Middle name or initial (optional)',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 105,
                      child: TextFormField(
                        controller: _guardianSuffix,
                        decoration: const InputDecoration(
                          labelText: 'Suffix',
                          hintText: 'Jr.',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: _guardianBirthDateFieldKey,
                  onTap: _selectGuardianBirthDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Guardian birth date',
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                      errorText: _guardianBirthDateError,
                    ),
                    child: Text(
                      _guardianBirthDate == null
                          ? 'Select date'
                          : _date(_guardianBirthDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _guardianSex,
                  decoration: const InputDecoration(labelText: 'Guardian sex'),
                  items: GuardianRelationshipOptions.sexes
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _guardianSex = value!;
                    _relationship = GuardianRelationshipOptions.defaultForSex(
                      value,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _phoneFieldKey,
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText:
                        _createAccount &&
                            _invitationChannel == GuardianInvitationChannel.sms
                        ? 'Mobile number'
                        : 'Mobile number (optional)',
                    errorText: _phoneError,
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _emailFieldKey,
                  controller: _email,
                  decoration: InputDecoration(
                    labelText:
                        _createAccount &&
                            _invitationChannel ==
                                GuardianInvitationChannel.email
                        ? 'Email address'
                        : 'Email address (optional)',
                    errorText: _emailError,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _addressFieldKey,
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Home address'),
                  textCapitalization: TextCapitalization.words,
                  validator: _required,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Guardian record access',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                RadioGroup<bool>(
                  groupValue: _createAccount,
                  onChanged: (value) => setState(() {
                    _createAccount = value ?? false;
                    _phoneError = null;
                    _emailError = null;
                  }),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        value: true,
                        title: const Text('Online guardian account'),
                        subtitle: const Text(
                          'Send an activation invitation. The guardian creates their own password.',
                        ),
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        value: false,
                        title: const Text('Health-worker-managed record'),
                        subtitle: const Text(
                          'No login is required. Online access can be requested later.',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_createAccount) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GuardianInvitationChannel>(
                    initialValue: _invitationChannel,
                    decoration: const InputDecoration(
                      labelText: 'Invitation delivery',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: GuardianInvitationChannel.sms,
                        child: Text('SMS'),
                      ),
                      if (!RepositoryRegistry.instance.environment.isLive)
                        const DropdownMenuItem(
                          value: GuardianInvitationChannel.email,
                          child: Text('Mock email'),
                        ),
                      const DropdownMenuItem(
                        value: GuardianInvitationChannel.printedSlip,
                        child: Text('Printed activation slip'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _invitationChannel = value!;
                      _phoneError = null;
                      _emailError = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    RepositoryRegistry.instance.environment.isLive
                        ? 'SMS sends one activation message to the guardian’s saved mobile number. The code is also shown once so it can be printed if delivery fails.'
                        : 'SMS and email delivery are simulated. No third-party provider is connected.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
                const Divider(height: 32),
                const _SectionTitle(
                  icon: Icons.child_care_rounded,
                  title: 'Child Information',
                ),
                const SizedBox(height: 12),
                if (_additionalChildren.isNotEmpty) ...[
                  Text(
                    'Children added (${_additionalChildren.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ..._additionalChildren.asMap().entries.map(
                    (entry) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.child_care_rounded),
                        title: Text(entry.value.fullName),
                        subtitle: Text(
                          '${_date(entry.value.birthDate)} • ${entry.value.relationship}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove child',
                          onPressed: () => setState(
                            () => _additionalChildren.removeAt(entry.key),
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: _childFirstNameFieldKey,
                        controller: _childFirstName,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        key: _childLastNameFieldKey,
                        controller: _childLastName,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _childMiddleName,
                        decoration: const InputDecoration(
                          labelText: 'Middle name or initial (optional)',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 105,
                      child: TextFormField(
                        controller: _childSuffix,
                        decoration: const InputDecoration(
                          labelText: 'Suffix',
                          hintText: 'III',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  key: _childBirthDateFieldKey,
                  onTap: _selectBirthDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Birth date',
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                      errorText: _birthDateError,
                    ),
                    child: Text(
                      _birthDate == null ? 'Select date' : _date(_birthDate!),
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
                  key: ValueKey(_guardianSex),
                  initialValue: _relationship,
                  decoration: const InputDecoration(
                    labelText: 'Relationship to guardian',
                  ),
                  items: GuardianRelationshipOptions.forSex(_guardianSex)
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
                  title: const Text(
                    'Guardian identity and authority confirmed',
                  ),
                  subtitle: Text(
                    _authorizationError ??
                        'Required before linking this child record.',
                    style: _authorizationError == null
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _addAnotherChild,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add This Child & Enter Another'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _review,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(_saving ? 'Saving...' : 'Review Registration'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
  Future<Uint8List> _buildActivationSlip(
    GuardianRegistrationResult result,
  ) async {
    final invitation = result.invitation!;
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(44),
        build: (_) => pw.Center(
          child: pw.Container(
            width: 390,
            padding: const pw.EdgeInsets.all(28),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'GUARDIAN ONLINE ACCESS',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Barangay Bugo Health Center',
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 24),
                _slipField('Guardian', result.guardian.fullName),
                _slipField('Guardian ID', result.guardian.guardianCode),
                _slipField('Activation code', invitation.invitationCode),
                _slipField('Expires', _printDate(invitation.expiresAt)),
                pw.SizedBox(height: 18),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Use the Activate Guardian Access option in VaxLink. Enter the one-time activation code above. Your Guardian ID will become your login ID, and you will create a private password during activation.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Keep this slip private. The activation code can be used only once.',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return document.save();
  }

  pw.Widget _slipField(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  String _printDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _printActivationSlip(GuardianRegistrationResult result) =>
      Printing.layoutPdf(
        name: 'Guardian_Activation_${result.guardian.guardianCode}.pdf',
        onLayout: (_) => _buildActivationSlip(result),
      );
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.family_restroom_rounded),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Register a child and guardian. Families without a phone can use a health-worker-managed record and printed child QR.',
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 9),
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
