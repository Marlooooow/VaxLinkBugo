import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/advisory_insight.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_advisory_insight_repository.dart';

void main() {
  test('advisory insights retain evidence and require human review', () async {
    final repository = MockAdvisoryInsightRepository();
    final insights = await repository.getFacilityInsights();

    expect(insights, isNotEmpty);
    expect(
      insights.every((item) => item.sourceEntityIds.isNotEmpty),
      isTrue,
    );
    expect(
      insights.every((item) => item.analysisProvider.isNotEmpty),
      isTrue,
    );
    expect(
      insights.every((item) => item.status == AdvisoryInsightStatus.newInsight),
      isTrue,
    );

    final reviewed = await repository.updateStatus(
      insightId: insights.first.id,
      status: AdvisoryInsightStatus.reviewed,
      reviewedByUserId: 'USR-H-001',
    );

    expect(reviewed.status, AdvisoryInsightStatus.reviewed);
    expect(reviewed.reviewedByUserId, 'USR-H-001');
    expect(reviewed.reviewedAt, isNotNull);
  });
}
