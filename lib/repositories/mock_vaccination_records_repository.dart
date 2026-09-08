import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';

import '../models/pnip_schedule_entry.dart';
import '../models/vaccination_record_summary.dart';
import 'child_repository.dart';
import 'vaccination_records_repository.dart';
import 'vaccination_repository.dart';

class MockVaccinationRecordsRepository
    implements VaccinationRecordsRepository {
  final ChildRepository _children;
  final VaccinationRepository _vaccinations;

  const MockVaccinationRecordsRepository(this._children, this._vaccinations);

  @override
  Future<VaccinationRecordSummaryPage> getSummaries({
    String search = '',
    VaccinationRecordSummaryFilter filter =
        VaccinationRecordSummaryFilter.all,
    int pageSize = 20,
    VaccinationRecordSummaryCursor? cursor,
  }) async {
    final families = await _children.getHealthWorkerRegisteredFamilies();
    final uniqueChildren = <String, _MockChildOwner>{};
    for (final family in families) {
      for (final child in family.children) {
        uniqueChildren.putIfAbsent(
          child.id,
          () => _MockChildOwner(child: child, guardian: family.guardian),
        );
      }
    }

    final summaries = await Future.wait(
      uniqueChildren.values.map((owner) async {
        final history = await _vaccinations.getVaccinationHistory(
          owner.child.id,
        );
        final schedule = await _vaccinations.getVaccinationSchedule(
          owner.child,
        );
        final latest = history.isEmpty ? null : history.first;
        int statusCount(PnipDoseStatus status) =>
            schedule.where((entry) => entry.status == status).length;
        return VaccinationRecordSummary(
          child: owner.child,
          guardianId: owner.guardian.id,
          guardianCode: owner.guardian.guardianCode,
          guardianName: owner.guardian.fullName,
          recordedCount: history.length,
          completedCount: statusCount(PnipDoseStatus.completed),
          dueCount: statusCount(PnipDoseStatus.due),
          overdueCount: statusCount(PnipDoseStatus.overdue),
          upcomingCount: statusCount(PnipDoseStatus.upcoming),
          scheduleCount: schedule.length,
          latestVaccineName: latest?.vaccineName,
          latestDoseNumber: latest?.doseNumber,
          latestAdministeredOn: latest?.dateAdministered,
          sortAt: latest?.dateAdministered ?? owner.child.birthDate,
        );
      }),
    );
    summaries.sort((a, b) {
      final date = b.sortAt.compareTo(a.sortAt);
      return date != 0 ? date : b.child.id.compareTo(a.child.id);
    });

    final normalized = search.trim().toLowerCase();
    final filtered = summaries.where((summary) {
      final searchMatches = normalized.isEmpty ||
          summary.child.fullName.toLowerCase().contains(normalized) ||
          summary.child.id.toLowerCase().contains(normalized) ||
          summary.child.qrIdentifier.toLowerCase().contains(normalized) ||
          summary.guardianName.toLowerCase().contains(normalized) ||
          summary.guardianCode.toLowerCase().contains(normalized);
      if (!searchMatches) return false;
      return switch (filter) {
        VaccinationRecordSummaryFilter.all => true,
        VaccinationRecordSummaryFilter.recorded => summary.recordedCount > 0,
        VaccinationRecordSummaryFilter.dueNow => summary.dueCount > 0,
        VaccinationRecordSummaryFilter.overdue => summary.overdueCount > 0,
        VaccinationRecordSummaryFilter.upcoming => summary.upcomingCount > 0,
        VaccinationRecordSummaryFilter.completed => summary.isCompleted,
      };
    }).toList();
    final total = filtered.length;
    final afterCursor = cursor == null
        ? filtered
        : filtered.where((summary) {
            final date = summary.sortAt.compareTo(cursor.sortAt);
            return date < 0 ||
                (date == 0 && summary.child.id.compareTo(cursor.childId) < 0);
          }).toList();
    final safePageSize = pageSize.clamp(10, 50).toInt();
    final items = afterCursor.take(safePageSize).toList(growable: false);
    return VaccinationRecordSummaryPage(
      items: items,
      totalCount: total,
      hasMore: afterCursor.length > items.length,
      nextCursor: items.isEmpty ? null : items.last.cursor,
    );
  }
}

class _MockChildOwner {
  final ChildProfile child;
  final GuardianProfile guardian;

  const _MockChildOwner({required this.child, required this.guardian});
}
