import 'dart:convert';

import '../models/child_profile.dart';
import '../models/qr_scan_result.dart';
import 'qr_repository.dart';
import 'mock_child_repository.dart';

class MockQrRepository implements QrRepository {
  @override
  Future<QrScanResult?> simulateScan() async {
    await Future.delayed(const Duration(seconds: 2));

    final child = ChildProfile(
      id: 'CH-001',
      fullName: 'Sofia Santos',
      birthDate: DateTime(2025, 9, 14),
      sex: 'Female',
      qrIdentifier: 'QR-CH-001',
      relationship: 'Mother',
    );

    return QrScanResult(
      qrIdentifier: child.qrIdentifier,
      child: child,
      scannedAt: DateTime.now(),
    );
  }

  @override
  Future<QrScanResult?> findByIdentifier(String identifier) async {
    var resolvedIdentifier = identifier.trim();
    try {
      final payload = jsonDecode(resolvedIdentifier);
      if (payload is Map<String, dynamic> &&
          payload['type'] == 'child_identity' &&
          payload['version'] == 1) {
        resolvedIdentifier =
            payload['child_id'] as String? ??
            payload['qr_identifier'] as String? ??
            resolvedIdentifier;
      }
    } on FormatException {
      // Manual Child IDs and legacy QR identifiers are valid plain text.
    }
    final child = await MockChildRepository().findChildByIdentifier(
      resolvedIdentifier,
    );
    if (child == null) return null;
    return QrScanResult(
      qrIdentifier: child.qrIdentifier,
      child: child,
      scannedAt: DateTime.now(),
    );
  }
}
