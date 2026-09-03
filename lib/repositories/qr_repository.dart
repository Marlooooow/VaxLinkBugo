import '../models/qr_scan_result.dart';

abstract class QrRepository {
  Future<QrScanResult?> simulateScan();
  Future<QrScanResult?> findByIdentifier(String identifier);
}
