import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/advisory_insight.dart';
import 'package:qr_code_based_pediatric_vaccination/models/app_user.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/advisory_insight_repository.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/advisory_insights_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/theme/app_theme.dart';
import 'package:qr_code_based_pediatric_vaccination/screens/vaccine_inventory_details_screen.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/repository_registry.dart';
import 'package:qr_code_based_pediatric_vaccination/config/app_environment.dart';

class _Repository implements AdvisoryInsightRepository {
  int reads = 0;
  bool fail = false;
  AdvisoryInsight item = AdvisoryInsight(
    id: 'insight',
    insightCode: 'AI-1',
    type: AdvisoryInsightType.stockRisk,
    severity: AdvisoryInsightSeverity.high,
    status: AdvisoryInsightStatus.newInsight,
    title: 'Stock needs review',
    summary: 'Review available doses.',
    rationale: 'Low balance.',
    recommendedAction: 'Check inventory.',
    childId: null,
    childName: null,
    vaccineId: 'hepb',
    vaccineName: null,
    sourceEntityIds: [],
    sourceSnapshot: {},
    analysisProvider: 'test',
    analysisVersion: '1',
    generatedAt: DateTime(2026, 8, 1),
  );
  @override
  Future<List<AdvisoryInsight>> getFacilityInsights() async {
    reads++;
    return [item];
  }

  @override
  Future<AdvisoryInsight> updateStatus({
    required String insightId,
    required AdvisoryInsightStatus status,
    required String reviewedByUserId,
  }) async {
    if (fail) throw StateError('private backend failure');
    item = item.copyWith(
      status: status,
      reviewedByUserId: reviewedByUserId,
      reviewedAt: DateTime.now(),
    );
    return item;
  }
}

void main() {
  testWidgets('Insight action opens its linked vaccine stock', (tester) async {
    RepositoryRegistry.create(
      const AppEnvironment(
        dataMode: AppDataMode.mock,
        supabaseUrl: '',
        supabaseAnonKey: '',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdvisoryInsightsScreen(
          repository: _Repository(),
          initialInsightId: 'insight',
          healthWorker: const AppUser(
            id: 'worker',
            fullName: 'Nurse',
            role: UserRole.healthWorker,
            active: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View stock details'));
    await tester.tap(find.text('View stock details'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      tester
          .widget<VaccineInventoryDetailsScreen>(
            find.byType(VaccineInventoryDetailsScreen),
          )
          .vaccineId,
      'hepb',
    );
    expect(tester.takeException(), isNull);
  });
  for (final target in ['insight', 'missing-insight']) {
    testWidgets('Notification opens exact insight: $target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AdvisoryInsightsScreen(
            repository: _Repository(),
            initialInsightId: target,
            healthWorker: const AppUser(
              id: 'worker',
              fullName: 'Worker',
              role: UserRole.healthWorker,
              active: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      if (target == 'insight') {
        expect(find.text('Stock needs review'), findsOneWidget);
        expect(find.text('Why this appeared'), findsOneWidget);
      } else {
        expect(find.text('Stock needs review'), findsNothing);
        expect(
          find.textContaining('This insight is no longer available.'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('View all insights'));
      await tester.pumpAndSettle();
      expect(find.text('Stock needs review'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in ['Mark as reviewed', 'Dismiss insight', 'failed save']) {
    testWidgets('$action updates the card without regenerating insights', (
      tester,
    ) async {
      final repository = _Repository()..fail = action == 'failed save';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: AdvisoryInsightsScreen(
            repository: repository,
            healthWorker: const AppUser(
              id: 'worker',
              fullName: 'Worker',
              role: UserRole.healthWorker,
              active: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stock needs review'));
      await tester.pumpAndSettle();
      final button = find.text(
        action == 'failed save' ? 'Mark as reviewed' : action,
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.reads, 1);
      if (repository.fail) {
        expect(
          find.text('The insight could not be updated. Please try again.'),
          findsOneWidget,
        );
        expect(find.text('Mark as reviewed'), findsOneWidget);
      } else {
        expect(
          find.text(action == 'Mark as reviewed' ? 'REVIEWED' : 'DISMISSED'),
          findsOneWidget,
        );
        expect(find.text('Mark as reviewed'), findsNothing);
        expect(repository.item.reviewedByUserId, 'worker');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
