import 'package:flutter/material.dart';

import '../models/staff_notification.dart';
import '../repositories/staff_notification_repository.dart';
import '../utils/user_facing_error.dart';

class GuardianPasswordResetScreen extends StatefulWidget {
  final StaffNotification notification;
  final StaffNotificationRepository repository;

  const GuardianPasswordResetScreen({
    super.key,
    required this.notification,
    required this.repository,
  });

  @override
  State<GuardianPasswordResetScreen> createState() =>
      _GuardianPasswordResetScreenState();
}

class _GuardianPasswordResetScreenState
    extends State<GuardianPasswordResetScreen> {
  bool _resetting = false;
  String? _temporaryPassword;

  Future<void> _reset() async {
    final requestId = widget.notification.entityId;
    if (requestId == null || requestId.isEmpty || _resetting) return;
    setState(() => _resetting = true);
    try {
      final password = await widget.repository.resetGuardianPassword(requestId);
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _temporaryPassword = password;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            UserFacingError.message(
              error,
              fallback: 'The guardian password could not be reset.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Guardian password reset')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Password reset request',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Request details',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(widget.notification.body),
                const SizedBox(height: 14),
                _Detail(
                  label: 'Notification ID',
                  value: widget.notification.id,
                ),
                _Detail(
                  label: 'Reset request ID',
                  value: widget.notification.entityId ?? 'Unavailable',
                ),
                _Detail(
                  label: 'Received',
                  value: widget.notification.createdAt.toLocal().toString(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_temporaryPassword == null)
          FilledButton.icon(
            onPressed: _resetting ? null : _reset,
            icon: _resetting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.key_rounded),
            label: Text(_resetting ? 'Resetting password…' : 'Reset password'),
          )
        else
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Temporary password generated',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _temporaryPassword!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Give this password privately to the guardian. They must change it after signing in.',
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
