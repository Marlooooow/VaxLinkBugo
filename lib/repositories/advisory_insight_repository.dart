import 'package:qr_code_based_pediatric_vaccination/models/advisory_insight.dart';

abstract class AdvisoryInsightRepository {
  Future<List<AdvisoryInsight>> getFacilityInsights();

  Future<AdvisoryInsightPage> getFacilityInsightsPage({
    AdvisoryInsightSeverity? severity,
    AdvisoryInsightStatus? status,
    String? insightId,
    int limit = 20,
    int offset = 0,
  });

  Future<AdvisoryInsight> updateStatus({
    required String insightId,
    required AdvisoryInsightStatus status,
    required String reviewedByUserId,
  });
}

abstract interface class AdvisoryInsightGenerator {
  Future<int> generateFacilityInsights();
}
