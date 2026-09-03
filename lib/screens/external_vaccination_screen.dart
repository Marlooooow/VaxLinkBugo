import 'dart:convert';

import '../repositories/repository_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/referral.dart';
import '../repositories/referral_repository.dart';
import '../services/mock_identifier_generator.dart';
import 'referral_group_details_screen.dart';
import 'referral_history_screen.dart';

class ExternalVaccinationScreen extends StatefulWidget {
  const ExternalVaccinationScreen({super.key});

  @override
  State<ExternalVaccinationScreen> createState() =>
      _ExternalVaccinationScreenState();
}

class _ExternalVaccinationScreenState extends State<ExternalVaccinationScreen> {
  final ReferralRepository _repository =
      RepositoryRegistry.instance.referralRepository;

  bool _isScanning = false;

  Future<void> _scanReferralQr() async {
    if (_isScanning) {
      return;
    }

    final rawPayload = await showDialog<String>(
      context: context,
      builder: (_) => const _ReferralQrScannerDialog(),
    );
    if (rawPayload == null || rawPayload.trim().isEmpty || !mounted) return;

    setState(() => _isScanning = true);
    List<Referral> referrals = const [];
    try {
      final payload = jsonDecode(rawPayload);
      if (payload is! Map ||
          payload['type'] != 'vaccination_referral' ||
          payload['version'] != 1 ||
          payload['referral_group_id'] is! String ||
          payload['verification_token'] is! String) {
        throw const FormatException('This is not a supported referral QR code.');
      }
      final verification = await _repository.verifyReferralGroup(
        referralGroupId: payload['referral_group_id'] as String,
        verificationToken: payload['verification_token'] as String,
      );
      if (verification.canContinue) {
        referrals = await _repository.getReferralGroupByReferralId(
          verification.referralGroup!.referrals.first.referralId,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Referral QR could not be verified: $error')),
        );
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isScanning = false;
    });

    if (referrals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral QR could not be recognized.')),
      );

      return;
    }

    await _openReferralGroup(referrals);
  }

  Future<void> _enterReferralId() async {
    final referralId = await showDialog<String>(
      context: context,
      builder: (_) => const _ReferralIdDialog(),
    );

    if (referralId == null || referralId.isEmpty) {
      return;
    }

    final referrals = await _repository.getReferralGroupByReferralId(
      referralId,
    );

    if (!mounted) {
      return;
    }

    if (referrals.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Referral not found.')));

      return;
    }

    await _openReferralGroup(referrals);
  }

  Future<void> _openReferralGroup(List<Referral> referrals) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReferralGroupDetailsScreen(
          referrals: referrals,
          repository: _repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'External Vaccination',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: primary.withValues(alpha: 0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.medical_services_outlined,
                        color: primary,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Record External Vaccination',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Find a pending referral to record a '
                            'vaccination received from another '
                            'health facility.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Find Referral',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),

              const SizedBox(height: 7),

              Text(
                'Use the referral QR or enter the referral ID '
                'to retrieve the child referral record.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 20),

              // Scan QR
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _scanReferralQr,
                  icon: Icon(
                    _isScanning
                        ? Icons.hourglass_top_rounded
                        : Icons.qr_code_scanner_rounded,
                  ),
                  label: Text(
                    _isScanning ? 'Scanning Referral...' : 'Scan Referral QR',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Enter ID
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _isScanning ? null : _enterReferralId,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('Enter Referral ID'),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: _isScanning
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ReferralHistoryScreen(repository: _repository),
                          ),
                        ),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Referral History'),
                ),
              ),

              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Scanning the referral does not record '
                        'the vaccination yet. The referral must '
                        'first be verified before an external '
                        'vaccination can be entered.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Center(
                child: Text(
                  'Scan the referral QR or enter its referral ID to retrieve the saved referral.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferralIdDialog extends StatefulWidget {
  const _ReferralIdDialog();

  @override
  State<_ReferralIdDialog> createState() => _ReferralIdDialogState();
}

class _ReferralQrScannerDialog extends StatefulWidget {
  const _ReferralQrScannerDialog();

  @override
  State<_ReferralQrScannerDialog> createState() => _ReferralQrScannerDialogState();
}

class _ReferralQrScannerDialogState extends State<_ReferralQrScannerDialog> {
  final _camera = MobileScannerController(autoStart: false);
  final _controller = TextEditingController();
  bool _cameraStarted = false;
  bool _scanned = false;

  bool get _requiresHttps =>
      kIsWeb &&
      Uri.base.scheme != 'https' &&
      Uri.base.host != 'localhost' &&
      Uri.base.host != '127.0.0.1';

  Future<void> _startCamera() async {
    if (_requiresHttps || _cameraStarted) return;
    try {
      await _camera.start();
      if (mounted) setState(() => _cameraStarted = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera access is unavailable. Allow permission and try again.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify Referral QR'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _requiresHttps
                  ? const Center(child: Text('Camera scanning requires HTTPS on a mobile browser.'))
                  : MobileScanner(
                      controller: _camera,
                      onDetect: (capture) {
                        if (_scanned) return;
                        final value = capture.barcodes
                            .map((barcode) => barcode.rawValue)
                            .whereType<String>()
                            .firstOrNull;
                        if (value == null || value.trim().isEmpty) return;
                        _scanned = true;
                        Navigator.pop(context, value.trim());
                      },
                      errorBuilder: (_, __) => const Center(
                        child: Text('Camera access is needed to scan. You may paste the QR content below.'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (!_cameraStarted && !_requiresHttps)
            FilledButton.icon(
              onPressed: _startCamera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Allow camera access'),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Or paste referral QR content',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Verify'),
      ),
    ],
  );
}

class _ReferralIdDialogState extends State<_ReferralIdDialog> {
  final _controller = TextEditingController(text: 'REF-2026-000001');
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim().toUpperCase();
    if (!IdentifierFormats.referral.hasMatch(value)) {
      setState(() {
        _errorText = 'Use the format REF-YYYY-000000.';
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Enter Referral ID',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Referral ID',
          hintText: 'e.g. REF-2026-000001',
          errorText: _errorText,
          border: OutlineInputBorder(),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: const Text('Find Referral'),
        ),
      ],
    );
  }
}
