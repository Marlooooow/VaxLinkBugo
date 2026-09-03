import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repositories/auth_repository.dart';
import '../repositories/demo_repository.dart';
import '../utils/user_facing_error.dart';

class GuardianActivationScreen extends StatefulWidget {
  final AuthRepository authRepository;

  const GuardianActivationScreen({super.key, required this.authRepository});

  @override
  State<GuardianActivationScreen> createState() =>
      _GuardianActivationScreenState();
}

class _GuardianActivationScreenState extends State<GuardianActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _saving = false;
  String? _codeError;
  String? _generalError;

  bool get _isDemo => widget.authRepository is DemoRepository;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  String _normalizeActivationCode(String value) {
    final compact = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (compact.startsWith('ACT')) {
      return 'ACT-${compact.substring(3)}';
    }
    return compact;
  }

  Future<void> _pasteActivationCode() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final value = clipboard?.text?.trim() ?? '';
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No activation code was found to paste.')),
      );
      return;
    }
    final embedded = RegExp(
      r'ACT(?:[\s-]*[0-9A-F]){32}',
      caseSensitive: false,
    ).firstMatch(value)?.group(0);
    final normalized = _normalizeActivationCode(embedded ?? value);
    _code.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    setState(() {
      _codeError = null;
      _generalError = null;
    });
  }

  void _fillPrototypeInvitation() {
    _code.text = 'ACT-000101';
    setState(() {
      _codeError = null;
      _generalError = null;
    });
  }

  Future<void> _activate() async {
    if (_saving) return;
    final normalizedCode = _normalizeActivationCode(_code.text);
    _code.value = TextEditingValue(
      text: normalizedCode,
      selection: TextSelection.collapsed(offset: normalizedCode.length),
    );
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _codeError = null;
      _generalError = null;
    });
    try {
      final activation = await widget.authRepository.activateGuardianInvitation(
        activationCode: normalizedCode,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.green,
                  size: 38,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Online Access Activated',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'The guardian account is securely linked to the existing family and child records.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Save these credentials. The password must be changed after the first sign-in.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SelectableText('Guardian ID / Login ID: ${activation.username}'),
              const SizedBox(height: 4),
              SelectableText('Temporary password: ${activation.temporaryPassword}'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Continue to Sign In'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted) {
        Navigator.pop(context, (
          username: activation.username,
          password: activation.temporaryPassword,
        ));
      }
    } catch (error) {
      if (!mounted) return;
      final message = UserFacingError.message(
        error,
        fallback:
            'Activation could not be completed. Check your connection and try again.',
      );
      setState(() {
        _saving = false;
        if (message.toLowerCase().contains('activation code') ||
            message.toLowerCase().contains('invitation')) {
          _codeError = message;
        } else {
          _generalError = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Activate Guardian Access',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'For guardians registered as walk-ins at the health center. Enter the one-time activation code provided by the health worker. Your Guardian ID will be your login ID, and the system will issue a temporary password that must be changed after your first sign-in.',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          if (_generalError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_generalError!)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_isDemo) ...[
            Material(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.045),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.16),
                ),
              ),
              child: InkWell(
                onTap: _saving ? null : _fillPrototypeInvitation,
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(child: Icon(Icons.mark_email_read_outlined)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use Elena Dela Cruz invitation',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'ACT-000101 • credentials are generated automatically',
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.touch_app_outlined),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          TextFormField(
            controller: _code,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            enableInteractiveSelection: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
              LengthLimitingTextInputFormatter(64),
            ],
            decoration: InputDecoration(
              labelText: 'Activation code',
              hintText: _isDemo
                  ? 'ACT-000001'
                  : 'Paste the code from your health center',
              errorText: _codeError,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste activation code',
                onPressed: _saving ? null : _pasteActivationCode,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
            onChanged: (_) {
              if (_codeError != null || _generalError != null) {
                setState(() {
                  _codeError = null;
                  _generalError = null;
                });
              }
            },
            textCapitalization: TextCapitalization.characters,
            validator: (value) {
              final missing = _required(value);
              if (missing != null) return missing;
              final normalized = _normalizeActivationCode(value ?? '');
              if (!_isDemo &&
                  !RegExp(r'^ACT-[0-9A-F]{32}$').hasMatch(normalized)) {
                return 'Enter valid activation code provided by your health center.';
              }
              return null;
            },
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _saving ? null : _activate,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_outlined),
            label: Text(_saving ? 'Activating...' : 'Activate Online Access'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ],
      ),
    ),
  );
}
