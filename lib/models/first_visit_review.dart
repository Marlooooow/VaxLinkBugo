class FirstVisitReview {
  final String id;
  final String reviewCode;
  final String childId;
  final bool hasDocumentedPreviousVaccinations;
  final DateTime reviewedAt;
  final String reviewedByUserId;

  const FirstVisitReview({
    required this.id,
    required this.reviewCode,
    required this.childId,
    required this.hasDocumentedPreviousVaccinations,
    required this.reviewedAt,
    required this.reviewedByUserId,
  });

  FirstVisitReview.pending({
    required this.childId,
    required this.hasDocumentedPreviousVaccinations,
  }) : id = '',
       reviewCode = '',
       reviewedAt = DateTime(1970),
       reviewedByUserId = '';

  Map<String, Object?> toJson() => {
    'id': id,
    'review_code': reviewCode,
    'child_id': childId,
    'has_documented_previous_vaccinations': hasDocumentedPreviousVaccinations,
    'reviewed_at': reviewedAt.toIso8601String(),
    'reviewed_by': reviewedByUserId,
  };
}
