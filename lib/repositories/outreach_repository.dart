import '../models/outreach_session.dart';
import '../models/vaccination_record.dart';
import '../models/vaccination_screening.dart';
import '../models/vaccine_batch.dart';
import '../models/vaccine_inventory.dart';

class OutreachPage<T> {
  final List<T> items;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;

  const OutreachPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
  });
}

abstract class OutreachRepository {
  Future<List<OutreachSession>> getSessions();
  Future<OutreachPage<OutreachSession>> getSessionsPage({
    String search = '',
    OutreachSessionStatus? status,
    int limit = 20,
    int offset = 0,
  });
  Future<OutreachSession> getSession(String sessionId);
  Future<OutreachSession> createSession({
    required String title,
    required String location,
    required DateTime scheduledOn,
    String notes = '',
  });
  Future<List<OutreachStockAllocation>> getAllocations(String sessionId);
  Future<List<VaccineBatch>> getEligibleBatches();
  Future<OutreachPage<VaccineBatch>> getEligibleBatchesPage({
    String search = '',
    int limit = 20,
    int offset = 0,
  });
  Future<List<VaccineInventory>> getSessionInventory(String sessionId);
  Future<void> releaseStock({
    required String sessionId,
    required String batchId,
    required int quantity,
  });
  Future<OutreachSession> startSession({
    required String sessionId,
    required bool packagingIntact,
    required bool coldChainVerified,
    required String vvmStatus,
    String notes = '',
  });
  Future<void> recordVaccinations({
    required String sessionId,
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
  });
  Future<void> recordDisposition({
    required String sessionId,
    required String allocationId,
    required OutreachStockDisposition disposition,
    required int quantity,
    required String reason,
  });
  Future<OutreachSession> submitSession(String sessionId, {String notes = ''});
  Future<OutreachSession> completeSession(String sessionId);
}

class UnavailableOutreachRepository implements OutreachRepository {
  const UnavailableOutreachRepository();
  Never _unavailable() => throw StateError(
    'Outreach immunization requires a live database connection.',
  );
  @override
  Future<OutreachSession> completeSession(String sessionId) async =>
      _unavailable();
  @override
  Future<OutreachSession> createSession({
    required String title,
    required String location,
    required DateTime scheduledOn,
    String notes = '',
  }) async => _unavailable();
  @override
  Future<List<OutreachStockAllocation>> getAllocations(
    String sessionId,
  ) async => _unavailable();
  @override
  Future<List<VaccineBatch>> getEligibleBatches() async => _unavailable();
  @override
  Future<OutreachPage<VaccineBatch>> getEligibleBatchesPage({
    String search = '',
    int limit = 20,
    int offset = 0,
  }) async => _unavailable();
  @override
  Future<OutreachSession> getSession(String sessionId) async => _unavailable();
  @override
  Future<List<VaccineInventory>> getSessionInventory(String sessionId) async =>
      _unavailable();
  @override
  Future<List<OutreachSession>> getSessions() async => _unavailable();
  @override
  Future<OutreachPage<OutreachSession>> getSessionsPage({
    String search = '',
    OutreachSessionStatus? status,
    int limit = 20,
    int offset = 0,
  }) async => _unavailable();
  @override
  Future<void> recordDisposition({
    required String sessionId,
    required String allocationId,
    required OutreachStockDisposition disposition,
    required int quantity,
    required String reason,
  }) async => _unavailable();
  @override
  Future<void> recordVaccinations({
    required String sessionId,
    required VaccinationScreening screening,
    required List<VaccinationRecord> records,
  }) async => _unavailable();
  @override
  Future<void> releaseStock({
    required String sessionId,
    required String batchId,
    required int quantity,
  }) async => _unavailable();
  @override
  Future<OutreachSession> startSession({
    required String sessionId,
    required bool packagingIntact,
    required bool coldChainVerified,
    required String vvmStatus,
    String notes = '',
  }) async => _unavailable();
  @override
  Future<OutreachSession> submitSession(
    String sessionId, {
    String notes = '',
  }) async => _unavailable();
}
