class MockIdentifier {
  final String id;
  final String code;

  const MockIdentifier({required this.id, required this.code});
}

class MockIdentifierGenerator {
  static int _uuidCounter = 100;
  static final Map<String, int> _codeCounters = {};

  static MockIdentifier next({required String prefix, int? year}) {
    final effectiveYear = year ?? DateTime.now().year;
    final sequence = (_codeCounters[prefix] ?? 0) + 1;
    _codeCounters[prefix] = sequence;
    _uuidCounter++;
    return MockIdentifier(
      id: uuidFor(_uuidCounter),
      code: '$prefix-$effectiveYear-${sequence.toString().padLeft(6, '0')}',
    );
  }

  static void reserve(String prefix, int sequence) {
    final current = _codeCounters[prefix] ?? 0;
    if (sequence > current) _codeCounters[prefix] = sequence;
  }

  static String uuidFor(int value) {
    final suffix = value.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }

  static String verificationTokenFor(String id) {
    final compact = id.replaceAll('-', '');
    return 'mock-v1-${compact.substring(compact.length - 16)}';
  }
}

class IdentifierFormats {
  static final guardian = RegExp(r'^GRD-\d{4}-\d{6}$');
  static final child = RegExp(r'^CH-\d{4}-\d{6}$');
  static final guardianChildLink = RegExp(r'^GCL-\d{4}-\d{6}$');
  static final guardianCorrection = RegExp(r'^GCOR-\d{4}-\d{6}$');
  static final childCorrection = RegExp(r'^CCOR-\d{4}-\d{6}$');
  static final firstVisitReview = RegExp(r'^FVR-\d{4}-\d{6}$');
  static final guardianInvitation = RegExp(r'^GINV-\d{4}-\d{6}$');
  static final referralGroup = RegExp(r'^RGRP-\d{4}-\d{6}$');
  static final referral = RegExp(r'^REF-\d{4}-\d{6}$');
  static final externalVisit = RegExp(r'^EV-\d{4}-\d{6}$');
  static final vaccinationRecord = RegExp(r'^VR-\d{4}-\d{6}$');
  static final childVaccinationRecord = RegExp(r'^VAX-\d{4}-\d{6}$');
  static final vaccinationScreening = RegExp(r'^SCR-\d{4}-\d{6}$');
  static final correction = RegExp(r'^COR-\d{4}-\d{6}$');
  static final vaccineBatch = RegExp(r'^VBAT-\d{4}-\d{6}$');
  static final inventoryTransaction = RegExp(r'^ITXN-\d{4}-\d{6}$');
}
