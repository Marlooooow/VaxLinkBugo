import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../repositories/auth_repository.dart';
import '../utils/user_facing_error.dart';
import 'app_shell.dart';

class ChangePasswordScreen extends StatefulWidget {
  final AppUser user;
  final AuthRepository authRepository;
  final bool requiredChange;

  const ChangePasswordScreen({
    super.key,
    required this.user,
    required this.authRepository,
    this.requiredChange = true,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _current = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.authRepository.changePassword(
        _password.text,
        currentPassword: widget.requiredChange ? null : _current.text,
      );
      if (!mounted) return;
      if (!widget.requiredChange) {
        Navigator.pop(context, true);
        return;
      }
      final user = AppUser(
        id: widget.user.id,
        fullName: widget.user.fullName,
        role: widget.user.role,
        active: widget.user.active,
        isAdministrator: widget.user.isAdministrator,
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AppShell(user: user, authRepository: widget.authRepository),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'Password could not be changed. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.requiredChange ? 'Change temporary password' : 'Change password',
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.lock_reset_rounded, size: 56),
          const SizedBox(height: 18),
          Text(
            widget.requiredChange
                ? 'Create your private password'
                : 'Update your password',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            widget.requiredChange
                ? 'Your temporary password can no longer be used after this step.'
                : 'Enter your current password before creating a new one.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!widget.requiredChange) ...[
            TextFormField(
              controller: _current,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your current password.'
                  : null,
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => value == null || value.length < 8
                ? 'Use at least 8 characters.'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
            validator: (value) =>
                value != _password.text ? 'Passwords do not match.' : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save password'),
          ),
        ],
      ),
    ),
  );
}
