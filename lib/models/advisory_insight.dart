enum AdvisoryInsightType { delayedVaccination, stockRisk, waitlistPressure }

enum AdvisoryInsightSeverity { low, medium, high }

enum AdvisoryInsightStatus { newInsight, reviewed, actioned, dismissed }

class AdvisoryInsightSummary {
  final int high;
  final int medium;
  final int newCount;

  const AdvisoryInsightSummary({
    this.high = 0,
    this.medium = 0,
    this.newCount = 0,
  });
}

class AdvisoryInsightPage {
  final List<AdvisoryInsight> items;
  final AdvisoryInsightSummary summary;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;

  const AdvisoryInsightPage({
    required this.items,
    required this.summary,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
  });
}

class AdvisoryInsight {
  final String id;
  final String insightCode;
  final String? referenceCode;
  final AdvisoryInsightType type;
  final AdvisoryInsightSeverity severity;
  final AdvisoryInsightStatus status;
  final String title;
  final String summary;
  final String rationale;
  final String recommendedAction;
  final String? childId;
  final String? childName;
  final String? vaccineId;
  final String? vaccineName;
  final List<String> sourceEntityIds;
  final Map<String, Object?> sourceSnapshot;
  final String analysisProvider;
  final String analysisVersion;
  final DateTime generatedAt;
  final DateTime? reviewedAt;
  final String? reviewedByUserId;
  final String? reviewedByName;

  const AdvisoryInsight({
    required this.id,
    required this.insightCode,
    this.referenceCode,
    required this.type,
    required this.severity,
    required this.status,
    required this.title,
    required this.summary,
    required this.rationale,
    required this.recommendedAction,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.sourceEntityIds,
    required this.sourceSnapshot,
    required this.analysisProvider,
    required this.analysisVersion,
    required this.generatedAt,
    this.reviewedAt,
    this.reviewedByUserId,
    this.reviewedByName,
  });

  AdvisoryInsight copyWith({
    AdvisoryInsightStatus? status,
    DateTime? reviewedAt,
    String? reviewedByUserId,
    String? reviewedByName,
  }) => AdvisoryInsight(
    id: id,
    insightCode: insightCode,
    referenceCode: referenceCode,
    type: type,
    severity: severity,
    status: status ?? this.status,
    title: title,
    summary: summary,
    rationale: rationale,
    recommendedAction: recommendedAction,
    childId: childId,
    childName: childName,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    sourceEntityIds: sourceEntityIds,
    sourceSnapshot: sourceSnapshot,
    analysisProvider: analysisProvider,
    analysisVersion: analysisVersion,
    generatedAt: generatedAt,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
    reviewedByName: reviewedByName ?? this.reviewedByName,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'insight_code': insightCode,
    'reference_code': referenceCode,
    'type': type.name,
    'severity': severity.name,
    'status': status.name,
    'title': title,
    'summary': summary,
    'rationale': rationale,
    'recommended_action': recommendedAction,
    'child_id': childId,
    'child_name': childName,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'source_entity_ids': sourceEntityIds,
    'source_snapshot': sourceSnapshot,
    'analysis_provider': analysisProvider,
    'analysis_version': analysisVersion,
    'generated_at': generatedAt.toIso8601String(),
    'reviewed_at': reviewedAt?.toIso8601String(),
    'reviewed_by_user_id': reviewedByUserId,
    'reviewed_by_name': reviewedByName,
  };
}
