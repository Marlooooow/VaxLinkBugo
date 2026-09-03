import '../models/advisory_insight.dart';

abstract class AdvisoryInsightRepository {
  Future<List<AdvisoryInsight>> getFacilityInsights();

  Future<AdvisoryInsight> updateStatus({
    required String insightId,
    required AdvisoryInsightStatus status,
    required String reviewedByUserId,
  });
}
