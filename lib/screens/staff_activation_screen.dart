import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/auth_repository.dart';
import '../utils/user_facing_error.dart';
import '../widgets/app_loading.dart';

class StaffActivationScreen extends StatefulWidget {
  final AuthRepository authRepository;

  const StaffActivationScreen({super.key, required this.authRepository});

  @override
  State<StaffActivationScreen> createState() => _StaffActivationScreenState();
}

class _StaffActivationScreenState extends State<StaffActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pasteCode() async {
    final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted || value == null || value.isEmpty) return;
    setState(() {
      _code.text = value.toUpperCase();
      _error = null;
    });
  }

  Future<void> _activate() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.authRepository.activateStaffInvitation(
        activationCode: _code.text,
      );
      if (!mounted) return;
      final useCredentials = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.verified_user_rounded, size: 42),
          title: const Text('Staff access activated'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use these temporary credentials for your first sign-in. '
                'You will be required to create a private password.',
              ),
              const SizedBox(height: 16),
              const Text('Staff ID', style: TextStyle(fontSize: 12)),
              SelectableText(
                result.username.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text('Temporary password', style: TextStyle(fontSize: 12)),
              SelectableText(
                result.temporaryPassword,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue to sign in'),
            ),
          ],
        ),
      );
      if (!mounted || useCredentials != true) return;
      Navigator.pop(context, (
        username: result.username,
        password: result.temporaryPassword,
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = UserFacingError.message(
          error,
          fallback: 'Staff access could not be activated. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Activate Staff Access',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: AppLoadingOverlay(
      visible: _saving,
      title: 'Activating staff access',
      message: 'Creating and securely linking your staff account.',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'Enter the one-time activation code issued by the administrator. '
                'Your Staff ID will become your login ID.',
                style: TextStyle(height: 1.4),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_error!),
              ),
            ],
            const SizedBox(height: 18),
            TextFormField(
              controller: _code,
              enabled: !_saving,
              autocorrect: false,
              enableSuggestions: false,
              enableInteractiveSelection: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                LengthLimitingTextInputFormatter(72),
              ],
              decoration: InputDecoration(
                labelText: 'Staff activation code',
                hintText: 'STF-ACT-...',
                suffixIcon: IconButton(
                  tooltip: 'Paste activation code',
                  onPressed: _saving ? null : _pasteCode,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
              validator: (value) {
                final normalized = value?.trim().toUpperCase() ?? '';
                if (normalized.isEmpty) return 'Enter the activation code.';
                if (!RegExp(r'^STF-ACT-[0-9A-F]{32}$').hasMatch(normalized)) {
                  return 'Enter a valid staff activation code.';
                }
                return null;
              },
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _activate,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Activate Staff Access'),
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
