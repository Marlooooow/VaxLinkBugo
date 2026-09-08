import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';

Future<void> showGuardianActivationCodeDialog(
  BuildContext context,
  GuardianInvitation invitation, [
  String? guardianCode,
]) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (dialogContext) => AlertDialog(
    title: const Text('Guardian activation code'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give this code privately to the guardian. Their Guardian ID is the login ID, and the system will issue a temporary password during activation.',
          ),
          const SizedBox(height: 16),
          SelectableText(
            invitation.invitationCode,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (guardianCode != null && guardianCode.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Guardian ID / Login ID'),
            const SizedBox(height: 4),
            SelectableText(
              guardianCode,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Expires ${MaterialLocalizations.of(dialogContext).formatMediumDate(invitation.expiresAt.toLocal())}.',
          ),
          const SizedBox(height: 8),
          const Text(
            'The code is shown only now. No SMS or email has been sent. Reissuing a code cancels any previous pending code.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(
            ClipboardData(text: invitation.invitationCode),
          );
          if (dialogContext.mounted) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Activation code copied.')),
            );
          }
        },
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Copy for guardian'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Done'),
      ),
    ],
  ),
);
