enum FirstVisitHistoryStatus { verifiedRecords, unknownHistory, confirmedNone }

class FirstVisitReview {
  final String id;
  final String reviewCode;
  final String childId;
  final FirstVisitHistoryStatus historyStatus;
  final String notes;
  final DateTime reviewedAt;
  final String reviewedByUserId;

  const FirstVisitReview({
    required this.id,
    required this.reviewCode,
    required this.childId,
    required this.historyStatus,
    this.notes = '',
    required this.reviewedAt,
    required this.reviewedByUserId,
  });

  FirstVisitReview.pending({
    required this.childId,
    required this.historyStatus,
    this.notes = '',
  }) : id = '',
       reviewCode = '',
       reviewedAt = DateTime(1970),
       reviewedByUserId = '';

  bool get hasDocumentedPreviousVaccinations =>
      historyStatus == FirstVisitHistoryStatus.verifiedRecords;

  Map<String, Object?> toJson() => {
    'id': id,
    'review_code': reviewCode,
    'child_id': childId,
    'has_documented_previous_vaccinations': hasDocumentedPreviousVaccinations,
    'history_status': historyStatus.name,
    'history_notes': notes,
    'reviewed_at': reviewedAt.toIso8601String(),
    'reviewed_by': reviewedByUserId,
  };
}
