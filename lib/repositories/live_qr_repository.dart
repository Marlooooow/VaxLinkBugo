import 'dart:convert';
import '../models/qr_scan_result.dart';
import 'child_repository.dart';
import 'qr_repository.dart';
import 'live_data_access.dart';

class LiveQrRepository implements QrRepository {
  final ChildRepository children;
  const LiveQrRepository(this.children);

  @override
  Future<QrScanResult?> simulateScan() async =>
      throw const LiveOperationUnavailable('Simulated QR scans in live mode');

  @override
  Future<QrScanResult?> findByIdentifier(String identifier) async {
    final rawValue = identifier.trim().replaceFirst('\ufeff', '');
    final candidates = <String>[];
    if (rawValue.startsWith('{')) {
      final payload = jsonDecode(rawValue);
      if (payload is! Map ||
          payload['type'] != 'child_identity' ||
          payload['version'] != 1) {
        throw const FormatException('This is not a supported child QR code.');
      }
      for (final key in const ['child_id', 'qr_identifier']) {
        final candidate = payload[key];
        if (candidate is String && candidate.trim().isNotEmpty) {
          candidates.add(candidate.trim());
        }
      }
    } else {
      candidates.add(rawValue);
    }
    for (final candidate in candidates.toSet()) {
      final child = await children.findChildByIdentifier(candidate);
      if (child != null) {
        return QrScanResult(
          qrIdentifier: child.qrIdentifier,
          child: child,
          scannedAt: DateTime.now(),
        );
      }
    }
    return null;
  }
}
