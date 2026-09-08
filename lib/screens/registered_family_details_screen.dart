import '../repositories/repository_registry.dart';
import 'package:flutter/material.dart';

import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_correction.dart';
import '../models/vaccination_schedule_state.dart';
import '../repositories/child_repository.dart';
import '../repositories/guardian_invitation_repository.dart';
import '../utils/user_facing_error.dart';
import '../widgets/guardian_activation_code_dialog.dart';
import '../theme/status_colors.dart';
import 'add_child_to_guardian_screen.dart';
import 'child_profile_screen.dart';
import 'edit_guardian_screen.dart';
import 'edit_child_screen.dart';
import 'child_qr_screen.dart';

class RegisteredFamilyDetailsScreen extends StatefulWidget {
  final RegisteredFamily family;
  final String registeredByUserId;

  const RegisteredFamilyDetailsScreen({
    super.key,
    required this.family,
    required this.registeredByUserId,
  });

  @override
  State<RegisteredFamilyDetailsScreen> createState() =>
      _RegisteredFamilyDetailsScreenState();
}

class _RegisteredFamilyDetailsScreenState
    extends State<RegisteredFamilyDetailsScreen> {
  late RegisteredFamily family = widget.family;
  GuardianCorrection? _lastGuardianCorrection;
  bool _issuingInvitation = false;
  bool _resettingGuardianPassword = false;

  Future<void> _refreshLiveFamily() async {
    if (!RepositoryRegistry.instance.environment.isLive) return;
    try {
      final refreshed = await RepositoryRegistry.instance.childRepository
          .getHealthWorkerRegisteredFamily(family.guardian.id);
      if (mounted && refreshed != null) setState(() => family = refreshed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The change was saved, but this view could not refresh. Reopen the family to see the latest details.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _issueInvitation() async {
    if (_issuingInvitation) return;
    final repository = RepositoryRegistry.instance.childRepository;
    if (repository is! GuardianInvitationIssuer) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Issue activation code?'),
        content: const Text(
          'Prepare a one-time code for this guardian. Any previous pending code will stop working. Give the new code to the guardian privately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Issue code'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _issuingInvitation = true);
    try {
      final result = await (repository as GuardianInvitationIssuer)
          .issueGuardianInvitation(family.guardian.id);
      if (!mounted) return;
      await showGuardianActivationCodeDialog(
        context,
        result.invitation,
        result.guardian.guardianCode,
      );
      if (!mounted) return;
      setState(
        () => family = RegisteredFamily(
          guardian: result.guardian.copyWith(clearInvitationCode: true),
          children: family.children,
          links: family.links,
        ),
      );
      await _refreshLiveFamily();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UserFacingError.message(
                error,
                fallback:
                    'The activation code could not be prepared. Please try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _issuingInvitation = false);
    }
  }

  String _date(DateTime value) =>
      '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year}';

  Future<void> _addChild() async {
    final result = await Navigator.push<ExistingGuardianChildResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddChildToGuardianScreen(
          guardian: family.guardian,
          registeredByUserId: widget.registeredByUserId,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      family = RegisteredFamily(
        guardian: family.guardian,
        children: [...family.children, result.child],
        links: [...family.links, result.link],
        invitation: family.invitation,
      );
    });
  }

  Future<void> _editGuardian() async {
    final result = await Navigator.push<GuardianCorrectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EditGuardianScreen(
          guardian: family.guardian,
          correctedByUserId: widget.registeredByUserId,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      family = RegisteredFamily(
        guardian: result.guardian,
        children: family.children,
        links: family.links,
        invitation: family.invitation,
      );
      _lastGuardianCorrection = result.correction;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Guardian correction saved.')));
    await _refreshLiveFamily();
  }

  Future<void> _editChild(ChildProfile child) async {
    final result = await Navigator.push<ChildCorrectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => EditChildScreen(
          child: child,
          guardianId: family.guardian.id,
          guardianSex: family.guardian.sex,
          correctedByUserId: widget.registeredByUserId,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final children = family.children
          .map((item) => item.id == result.child.id ? result.child : item)
          .toList(growable: false);
      final links = family.links
          .map(
            (link) => link.childId == result.child.id
                ? GuardianChildLink(
                    id: link.id,
                    guardianId: link.guardianId,
                    childId: link.childId,
                    relationship: result.child.relationship,
                    isPrimaryGuardian: link.isPrimaryGuardian,
                    authorizationConfirmed: link.authorizationConfirmed,
                    linkedAt: link.linkedAt,
                    linkedByUserId: link.linkedByUserId,
                  )
                : link,
          )
          .toList(growable: false);
      family = RegisteredFamily(
        guardian: family.guardian,
        children: children,
        links: links,
        invitation: family.invitation,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Child correction saved: ${result.correction.correctionCode}',
        ),
      ),
    );
  }

  Future<void> _resetGuardianPassword() async {
    final guardian = family.guardian;
    if (guardian.userId == null || _resettingGuardianPassword) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset guardian password?'),
        content: const Text(
          'A temporary password will be generated. The guardian must change it after signing in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resettingGuardianPassword = true);
    try {
      final password = await RepositoryRegistry
          .instance
          .staffNotificationRepository
          .resetGuardianPasswordForGuardian(guardian.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Temporary password generated'),
          content: SelectableText(
            'Guardian ID / Login ID:\n${guardian.guardianCode}\n\nTemporary password:\n$password\n\nGive these privately to the guardian. They must change the password after signing in.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset failed: $error')),
        );
    } finally {
      if (mounted) setState(() => _resettingGuardianPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardian = family.guardian;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Family Details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          _DetailsCard(
            title: 'Guardian Information',
            icon: Icons.person_outline_rounded,
            action: TextButton.icon(
              onPressed: _editGuardian,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            children: [
              _DetailRow(label: 'Guardian', value: guardian.fullName),
              _DetailRow(label: 'Sex', value: guardian.sex),
              _DetailRow(
                label: 'Birth date',
                value: guardian.birthDate == null
                    ? 'Not recorded'
                    : _date(guardian.birthDate!),
              ),
              _DetailRow(label: 'Guardian ID', value: guardian.guardianCode),
              _DetailRow(
                label: 'Profile ID',
                value: guardian.userId ?? 'Not linked — activation pending',
              ),
              _DetailRow(label: 'Address', value: guardian.address),
              _DetailRow(
                label: 'Mobile number',
                value: guardian.phoneNumber ?? 'Not provided',
              ),
              _DetailRow(
                label: 'Email',
                value: guardian.emailAddress ?? 'Not provided',
              ),
              _DetailRow(label: 'Record access', value: guardian.accessLabel),
              if (!RepositoryRegistry.instance.environment.isLive &&
                  guardian.invitationCode != null)
                _DetailRow(
                  label: 'Activation code',
                  value: guardian.invitationCode!,
                ),
              if (family.invitation != null) ...[
                _DetailRow(
                  label: 'Delivery',
                  value: family.invitation!.channelLabel,
                ),
                _DetailRow(
                  label: 'Destination',
                  value: family.invitation!.maskedDestination,
                ),
                _DetailRow(
                  label: 'Invitation status',
                  value: family.invitation!.statusLabel,
                ),
                _DetailRow(
                  label: 'Code expires',
                  value: _date(family.invitation!.expiresAt.toLocal()),
                ),
              ],
              if (guardian.userId != null) ...[
                const Divider(height: 28),
                Text(
                  'Account access',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this only when the guardian requests a password reset.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _resettingGuardianPassword
                        ? null
                        : _resetGuardianPassword,
                    icon: _resettingGuardianPassword
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset_rounded),
                    label: Text(
                      _resettingGuardianPassword
                          ? 'Resetting password…'
                          : 'Reset guardian password',
                    ),
                  ),
                ),
              ],
              if (RepositoryRegistry.instance.childRepository
                      is GuardianInvitationIssuer &&
                  guardian.userId == null &&
                  guardian.accessStatus !=
                      GuardianAccessStatus.accessDeclined &&
                  guardian.accessStatus !=
                      GuardianAccessStatus.accessDisabled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _issuingInvitation ? null : _issueInvitation,
                  icon: const Icon(Icons.key_outlined),
                  label: Text(
                    _issuingInvitation
                        ? 'Preparing code…'
                        : 'Issue activation code',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _DetailsCard(
            title: 'Registration Audit',
            icon: Icons.verified_user_outlined,
            children: [
              _DetailRow(
                label: 'Registered',
                value: _date(guardian.registeredAt),
              ),
              _DetailRow(
                label: 'Registered by',
                value: guardian.registeredByUserId.isEmpty
                    ? 'Legacy record'
                    : guardian.registeredByUserId,
              ),
              _DetailRow(
                label: 'Authorization',
                value: family.links.every((link) => link.authorizationConfirmed)
                    ? 'Confirmed'
                    : 'Needs review',
              ),

              if (_lastGuardianCorrection != null) ...[
                const Divider(height: 22),
                _DetailRow(
                  label: 'Last corrected',
                  value: _date(_lastGuardianCorrection!.correctedAt),
                ),
                _DetailRow(
                  label: 'Reason',
                  value: _lastGuardianCorrection!.reason,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Linked Children (${family.children.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addChild,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Child'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...family.children.map(
            (child) => _ChildDetailsCard(
              child: child,
              onEdit: () => _editChild(child),
              onQr: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChildQrScreen(child: child)),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChildProfileScreen(child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildDetailsCard extends StatelessWidget {
  final ChildProfile child;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onQr;

  const _ChildDetailsCard({
    required this.child,
    required this.onTap,
    required this.onEdit,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: const CircleAvatar(child: Icon(Icons.child_care_rounded)),
      title: Text(
        child.fullName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${child.id}\n${child.relationship}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder(
            future: RepositoryRegistry.instance.vaccinationRepository
                .getVaccinationSchedule(child),
            builder: (context, snapshot) => snapshot.hasData
                ? _StatusChip(state: summarizeSchedule(snapshot.data!))
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Child actions',
            onSelected: (value) {
              if (value == 'qr') onQr();
              if (value == 'edit') onEdit();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'qr',
                child: ListTile(
                  leading: Icon(Icons.qr_code_2_rounded),
                  title: Text('View / Print QR'),
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Correct Information'),
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: onTap,
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final VaccinationScheduleState state;
  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      VaccinationScheduleState.completed => StatusColors.completed,
      VaccinationScheduleState.dueNow => StatusColors.due,
      VaccinationScheduleState.upcoming => StatusColors.upcoming,
      VaccinationScheduleState.overdue => StatusColors.overdue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? action;

  const _DetailsCard({
    required this.title,
    required this.icon,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            if (action != null) ...[const Spacer(), action!],
          ],
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
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
