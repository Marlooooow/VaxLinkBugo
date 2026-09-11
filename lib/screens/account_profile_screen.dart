import 'package:flutter/material.dart';

import '../models/account_profile.dart';
import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/repository_registry.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_feedback.dart';
import 'change_password_screen.dart';

class AccountProfileScreen extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;

  const AccountProfileScreen({
    super.key,
    required this.user,
    required this.authRepository,
  });

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late final ProfileRepository _repository =
      RepositoryRegistry.instance.profileRepository;
  late Future<AccountProfile> _profile = _repository.getMyProfile(widget.user);

  void _reload() => setState(() {
    _profile = _repository.getMyProfile(widget.user);
  });

  Future<void> _editContact(AccountProfile profile) async {
    final result = await showModalBottomSheet<ProfileContactUpdate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ContactEditor(profile: profile),
    );
    if (result == null || !mounted) return;
    try {
      AccountProfile? updated;
      await runWithAppLoading(
        context,
        title: 'Updating profile',
        message: 'Saving your contact information securely.',
        operation: () async {
          updated = await _repository.updateMyContact(widget.user, result);
        },
      );
      if (!mounted) return;
      setState(() {
        _profile = Future.value(updated!);
      });
      AppFeedback.success(context, message: 'Contact information updated.');
    } catch (error) {
      if (!mounted) return;
      AppFeedback.failure(
        context,
        message: UserFacingError.message(
          error,
          fallback: 'Contact information could not be updated.',
        ),
      );
    }
  }

  Future<void> _changePassword() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(
          user: widget.user,
          authRepository: widget.authRepository,
          requiredChange: false,
        ),
      ),
    );
    if (changed == true && mounted) {
      AppFeedback.success(context, message: 'Password changed successfully.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'My Profile',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: FutureBuilder<AccountProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingView(
            title: 'Loading profile',
            message: 'Retrieving your account information.',
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your profile could not be loaded.'),
                TextButton(onPressed: _reload, child: const Text('Try again')),
              ],
            ),
          );
        }
        final profile = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _ProfileHeader(profile: profile),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Account Information',
                icon: Icons.badge_outlined,
                children: [
                  _DetailRow(
                    label: profile.isGuardian ? 'Guardian ID' : 'Staff ID',
                    value: profile.accountCode ?? 'Not assigned',
                  ),
                  _DetailRow(label: 'Login ID', value: profile.username),
                  _DetailRow(
                    label: 'Health center',
                    value: profile.facilityName ?? 'Not assigned',
                  ),
                  _DetailRow(label: 'Account status', value: profile.status),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline_rounded,
                children: [
                  _DetailRow(label: 'Full name', value: profile.user.fullName),
                  if (profile.isGuardian) ...[
                    _DetailRow(
                      label: 'Sex',
                      value: profile.sex ?? 'Not provided',
                    ),
                    _DetailRow(
                      label: 'Birth date',
                      value: profile.birthDate == null
                          ? 'Not provided'
                          : _date(profile.birthDate!),
                    ),
                  ] else ...[
                    _DetailRow(
                      label: 'Staff role',
                      value: profile.staffType ?? 'Health Worker',
                    ),
                    _DetailRow(
                      label: 'License number',
                      value: profile.licenseNumber ?? 'Not provided',
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Identity fields are protected. Ask an authorized administrator or health worker to correct them.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Contact Information',
                icon: Icons.contact_phone_outlined,
                action: profile.isGuardian || profile.accountCode != null
                    ? TextButton.icon(
                        onPressed: () => _editContact(profile),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      )
                    : null,
                children: [
                  _DetailRow(
                    label: 'Mobile number',
                    value: profile.phone ?? 'Not provided',
                  ),
                  _DetailRow(
                    label: 'Email',
                    value: profile.email ?? 'Not provided',
                  ),
                  if (profile.isGuardian)
                    _DetailRow(
                      label: 'Address',
                      value: profile.address ?? 'Not provided',
                    ),
                ],
              ),
              if (profile.isGuardian) ...[
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Linked Children (${profile.linkedChildren.length})',
                  icon: Icons.family_restroom_outlined,
                  children: profile.linkedChildren.isEmpty
                      ? const [Text('No approved child links found.')]
                      : profile.linkedChildren
                            .map(
                              (child) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  child: Icon(Icons.child_care_rounded),
                                ),
                                title: Text(child.name),
                                subtitle: Text(
                                  '${child.childCode} • ${child.relationship}',
                                ),
                              ),
                            )
                            .toList(),
                ),
              ],
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Security',
                icon: Icons.security_outlined,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password'),
                    subtitle: const Text('Your current password is required.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePassword,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  static String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';
}

class _ContactEditor extends StatefulWidget {
  final AccountProfile profile;
  const _ContactEditor({required this.profile});

  @override
  State<_ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<_ContactEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _email = TextEditingController(text: widget.profile.email ?? '');
  late final _address = TextEditingController(
    text: widget.profile.address ?? '',
  );

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _phoneValidator(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (!RegExp(r'^(09\d{9}|9\d{9}|639\d{9})$').hasMatch(digits)) {
      return 'Enter a valid Philippine mobile number.';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProfileContactUpdate(
        phone: _phone.text,
        email: _email.text,
        address: widget.profile.isGuardian ? _address.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _formKey,
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Edit Contact Information',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number'),
            validator: _phoneValidator,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address'),
            validator: _emailValidator,
          ),
          if (widget.profile.isGuardian) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Home address'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Home address is required.'
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
          ),
        ],
      ),
    ),
  );
}

class _ProfileHeader extends StatelessWidget {
  final AccountProfile profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            child: Icon(
              profile.isGuardian
                  ? Icons.person_rounded
                  : Icons.medical_services_rounded,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.user.fullName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.isGuardian
                      ? 'Guardian account'
                      : profile.staffType ?? 'Health worker account',
                ),
              ],
            ),
          ),
          Chip(label: Text(profile.status)),
        ],
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? action;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
