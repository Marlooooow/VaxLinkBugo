import 'package:qr_code_based_pediatric_vaccination/models/child_profile.dart';

class QrScanResult {
  final String qrIdentifier;
  final ChildProfile child;
  final DateTime scannedAt;

  const QrScanResult({
    required this.qrIdentifier,
    required this.child,
    required this.scannedAt,
  });
}
