import 'package:qr_code_based_pediatric_vaccination/models/advisory_insight.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_appointment.dart';
import 'package:qr_code_based_pediatric_vaccination/models/vaccination_reminder.dart';
import 'package:qr_code_based_pediatric_vaccination/services/mock_scenario_clock.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_appointment_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_inventory_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_reminder_repository.dart';

import 'advisory_insight_repository.dart';

class MockAdvisoryInsightRepository
    implements AdvisoryInsightRepository, AdvisoryInsightGenerator {
  static final Map<String, AdvisoryInsight> _saved = {};

  @override
  Future<List<AdvisoryInsight>> getFacilityInsights() async {
    final reminders = await MockReminderRepository().getFacilityFollowUps();
    final inventory = await MockInventoryRepository().getInventoryOverview();
    final appointments = await MockAppointmentRepository()
        .getFacilityAppointments();
    final insights = <AdvisoryInsight>[];

    final overdueByChild = <String, List<VaccinationReminder>>{};
    for (final reminder in reminders.where(
      (item) => item.status == VaccinationReminderStatus.overdue,
    )) {
      overdueByChild.putIfAbsent(reminder.childId, () => []).add(reminder);
    }
    for (final entry in overdueByChild.entries) {
      final items = entry.value..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      final oldest = items.first;
      final daysDelayed = MockScenarioClock.today
          .difference(oldest.dueDate)
          .inDays;
      insights.add(
        _withSavedStatus(
          AdvisoryInsight(
            id: 'INS-DELAY-${oldest.childId}',
            insightCode: 'AI-DELAY-${oldest.childId}',
            type: AdvisoryInsightType.delayedVaccination,
            severity: daysDelayed >= 60 || items.length >= 3
                ? AdvisoryInsightSeverity.high
                : AdvisoryInsightSeverity.medium,
            status: AdvisoryInsightStatus.newInsight,
            title: 'Delayed vaccination follow-up',
            summary:
                '${oldest.childName} has ${items.length} overdue vaccine dose${items.length == 1 ? '' : 's'}.',
            rationale:
                'The oldest recorded PNIP due date is $daysDelayed days past due. The advisory did not calculate or replace the due date.',
            recommendedAction:
                'Review the child record and eligibility, then contact the guardian for follow-up.',
            childId: oldest.childId,
            childName: oldest.childName,
            vaccineId: oldest.vaccineId,
            vaccineName: oldest.vaccineName,
            sourceEntityIds: items.map((item) => item.id).toList(),
            sourceSnapshot: {
              'overdue_count': items.length,
              'oldest_due_date': oldest.dueDate.toIso8601String(),
              'days_delayed': daysDelayed,
            },
            analysisProvider: 'mock-advisory-engine',
            analysisVersion: 'phase9-v1',
            generatedAt: DateTime.now(),
          ),
        ),
      );
    }

    for (final stock in inventory.where(
      (item) => item.isUnavailable || item.isLowStock,
    )) {
      final affected = reminders
          .where(
            (item) =>
                item.vaccineId.toLowerCase() == stock.vaccineId.toLowerCase() &&
                item.status != VaccinationReminderStatus.completed &&
                item.status != VaccinationReminderStatus.dismissed,
          )
          .toList();
      if (affected.isEmpty) continue;
      insights.add(
        _withSavedStatus(
          AdvisoryInsight(
            id: 'INS-STOCK-${stock.vaccineId}',
            insightCode: 'AI-STOCK-${stock.vaccineId.toUpperCase()}',
            type: AdvisoryInsightType.stockRisk,
            severity: stock.isUnavailable
                ? AdvisoryInsightSeverity.high
                : AdvisoryInsightSeverity.medium,
            status: AdvisoryInsightStatus.newInsight,
            title: stock.isUnavailable
                ? 'Vaccine stock unavailable'
                : 'Low stock pressure',
            summary:
                '${stock.vaccineName} has ${stock.availableDoses} usable doses and ${affected.length} active reminder${affected.length == 1 ? '' : 's'}.',
            rationale:
                'The advisory compares the shared inventory balance with the current reminder queue.',
            recommendedAction: stock.isUnavailable
                ? 'Review referrals or waitlisting and prepare guardian communication.'
                : 'Review due dates and appointments before allocating remaining doses.',
            childId: null,
            childName: null,
            vaccineId: stock.vaccineId,
            vaccineName: stock.vaccineName,
            sourceEntityIds: [stock.id, ...affected.map((item) => item.id)],
            sourceSnapshot: {
              'available_doses': stock.availableDoses,
              'active_reminders': affected.length,
              'low_stock_threshold': stock.lowStockThreshold,
            },
            analysisProvider: 'mock-advisory-engine',
            analysisVersion: 'phase9-v1',
            generatedAt: DateTime.now(),
          ),
        ),
      );
    }

    final waitlisted = appointments
        .where((item) => item.status == VaccinationAppointmentStatus.waitlisted)
        .toList();
    if (waitlisted.isNotEmpty) {
      insights.add(
        _withSavedStatus(
          AdvisoryInsight(
            id: 'INS-WAITLIST-FACILITY',
            insightCode: 'AI-WAITLIST-001',
            type: AdvisoryInsightType.waitlistPressure,
            severity: waitlisted.length >= 5
                ? AdvisoryInsightSeverity.high
                : AdvisoryInsightSeverity.medium,
            status: AdvisoryInsightStatus.newInsight,
            title: 'Appointment waitlist needs review',
            summary:
                '${waitlisted.length} appointment${waitlisted.length == 1 ? ' is' : 's are'} waiting for a service slot.',
            rationale:
                'This summarizes appointment status only; it does not change PNIP priority or reserve stock.',
            recommendedAction:
                'Review stock, due dates, and facility capacity before offering slots.',
            childId: null,
            childName: null,
            vaccineId: null,
            vaccineName: null,
            sourceEntityIds: waitlisted.map((item) => item.id).toList(),
            sourceSnapshot: {'waitlisted_appointments': waitlisted.length},
            analysisProvider: 'mock-advisory-engine',
            analysisVersion: 'phase9-v1',
            generatedAt: DateTime.now(),
          ),
        ),
      );
    }

    insights.sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      return bySeverity == 0 ? a.title.compareTo(b.title) : bySeverity;
    });
    for (final insight in insights) {
      _saved[insight.id] = insight;
    }
    return List.unmodifiable(insights);
  }

  @override
  Future<AdvisoryInsightPage> getFacilityInsightsPage({
    AdvisoryInsightSeverity? severity,
    AdvisoryInsightStatus? status,
    String? insightId,
    int limit = 20,
    int offset = 0,
  }) async {
    final all = await getFacilityInsights();
    final filtered = all
        .where((item) {
          if (insightId != null) return item.id == insightId;
          if (status != null && item.status != status) return false;
          return severity == null || item.severity == severity;
        })
        .toList(growable: false);
    final safeOffset = offset.clamp(0, filtered.length).toInt();
    final end = (safeOffset + limit).clamp(safeOffset, filtered.length).toInt();
    return AdvisoryInsightPage(
      items: filtered.sublist(safeOffset, end),
      summary: AdvisoryInsightSummary(
        high: all
            .where((item) => item.severity == AdvisoryInsightSeverity.high)
            .length,
        medium: all
            .where((item) => item.severity == AdvisoryInsightSeverity.medium)
            .length,
        newCount: all
            .where((item) => item.status == AdvisoryInsightStatus.newInsight)
            .length,
      ),
      totalCount: filtered.length,
      hasMore: end < filtered.length,
      nextOffset: end,
    );
  }

  @override
  Future<int> generateFacilityInsights() async =>
      (await getFacilityInsights()).length;

  AdvisoryInsight _withSavedStatus(AdvisoryInsight generated) {
    final saved = _saved[generated.id];
    return saved == null
        ? generated
        : generated.copyWith(
            status: saved.status,
            reviewedAt: saved.reviewedAt,
            reviewedByUserId: saved.reviewedByUserId,
          );
  }

  @override
  Future<AdvisoryInsight> updateStatus({
    required String insightId,
    required AdvisoryInsightStatus status,
    required String reviewedByUserId,
  }) async {
    final current = _saved[insightId];
    if (current == null) {
      throw StateError('The advisory insight was not found.');
    }
    final updated = current.copyWith(
      status: status,
      reviewedAt: DateTime.now(),
      reviewedByUserId: reviewedByUserId,
    );
    _saved[insightId] = updated;
    return updated;
  }
}
