import '../repositories/repository_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../repositories/qr_repository.dart';
import '../repositories/live_qr_repository.dart';
import 'qr_scan_result_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final QrRepository _qrRepository = RepositoryRegistry.instance.qrRepository;
  final MobileScannerController _cameraController = MobileScannerController(
    autoStart: false,
  );
  final bool _liveMode =
      RepositoryRegistry.instance.qrRepository is LiveQrRepository;

  bool _isScanning = false;
  bool _cameraStarted = false;

  bool get _browserNeedsHttps =>
      kIsWeb &&
      Uri.base.scheme != 'https' &&
      Uri.base.host != 'localhost' &&
      Uri.base.host != '127.0.0.1';

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleDetectedCode(String code) async {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    await _cameraController.stop();
    try {
      final result = await _qrRepository.findByIdentifier(code);
      if (!mounted) return;
      if (result == null) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No child matched this QR code.')),
        );
        await _cameraController.start();
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QrScanResultScreen(result: result)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR lookup failed: $error')),
      );
      await _cameraController.start();
    }
  }

  Future<void> _retryCamera() async {
    try {
      await _cameraController.start();
      if (mounted) setState(() => _cameraStarted = true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Camera access is unavailable. Allow camera permission and try again.',
          ),
        ),
      );
    }
  }

  Future<void> _startCamera() async {
    if (_cameraStarted || _isScanning) return;
    if (_browserNeedsHttps) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Secure connection required'),
          content: const Text(
            'Mobile browsers only allow camera access on HTTPS pages. '
            'Open this app using an HTTPS web address, or install the Android app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    await _retryCamera();
  }

  Future<void> _scanQr() async {
    if (_qrRepository is LiveQrRepository) {
      await _startCamera();
      return;
    }
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    try {
      final result = await _qrRepository.simulateScan();

      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code could not be recognized.')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QrScanResultScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isScanning = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan error: $e')));
    }
  }

  Future<void> _enterChildId() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final identifier = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Enter Child ID',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Child ID or QR identifier',
              hintText: 'CH-2026-000101',
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a child identifier.'
                : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Find Child'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (identifier == null || !mounted) return;
    setState(() => _isScanning = true);
    final result = await _qrRepository.findByIdentifier(identifier);
    if (!mounted) return;
    setState(() => _isScanning = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No child matched that identifier.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QrScanResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan Child QR',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),

      // IMPORTANT:
      // Using SingleChildScrollView prevents the lower
      // buttons from being covered or squeezed by the layout.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          child: Column(
            children: [
              // Information
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Scan the child QR to retrieve the child record. '
                        'The QR is an identifier only and does not determine '
                        'the vaccination schedule.',
                        style: TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 35),

              // QR Area
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _liveMode
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: MobileScanner(
                          controller: _cameraController,
                          fit: BoxFit.cover,
                          placeholderBuilder: (context) => Center(
                            child: CircularProgressIndicator(
                              color: colorScheme.secondary,
                            ),
                          ),
                          errorBuilder: (context, error) => Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.no_photography_outlined,
                                  size: 42,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _browserNeedsHttps
                                      ? 'HTTPS is required for camera access'
                                      : 'Camera access is needed to scan',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _browserNeedsHttps
                                      ? 'This web address is not secure. Use HTTPS or install the Android app.'
                                      : 'Allow camera permission in your browser or device settings.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _startCamera,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try camera again'),
                                ),
                              ],
                            ),
                          ),
                          onDetect: (capture) {
                            final codes = capture.barcodes
                                .map((barcode) => barcode.rawValue)
                                .whereType<String>()
                                .toList(growable: false);
                            if (codes.isNotEmpty &&
                                codes.first.trim().isNotEmpty) {
                              _handleDetectedCode(codes.first);
                            }
                          },
                        ),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 150,
                            color: colorScheme.primary.withValues(alpha: 0.14),
                          ),
                          Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colorScheme.secondary,
                                width: 2,
                              ),
                            ),
                          ),
                          if (_isScanning)
                            Container(
                              width: 190,
                              height: 2,
                              color: colorScheme.secondary,
                            ),
                        ],
                      ),
              ),

              const SizedBox(height: 22),

              if (_liveMode && !_cameraStarted)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _startCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      _browserNeedsHttps
                          ? 'Camera requires HTTPS'
                          : 'Allow camera access',
                    ),
                  ),
                ),

              if (_liveMode && !_cameraStarted) const SizedBox(height: 12),

              Text(
                _isScanning ? 'Reading QR code...' : 'Ready to scan',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                _isScanning
                    ? 'Retrieving the child record.'
                    : _liveMode
                    ? 'Point the camera at the child QR code.'
                    : 'Tap the button below to simulate a QR scan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 35),

              if (!_liveMode)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanQr,
                    icon: Icon(
                      _isScanning
                          ? Icons.hourglass_top_rounded
                          : Icons.qr_code_scanner_rounded,
                    ),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan Child QR'),
                  ),
                ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _isScanning ? null : _enterChildId,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('Enter Child ID'),
                ),
              ),

              const SizedBox(height: 18),

              if (!_liveMode)
                Text(
                  'Demo mode: QR scanning is simulated',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
      