enum VaccinationScreeningOutcome { cleared, deferred, referred }

class VaccinationScreening {
  final String id;
  final String screeningCode;
  final String childId;
  final bool historyReviewed;
  final bool currentConditionAssessed;
  final bool contraindicationsReviewed;
  final bool guardianConsentConfirmed;
  final VaccinationScreeningOutcome outcome;
  final String notes;
  final DateTime screenedAt;
  final String screenedByUserId;

  const VaccinationScreening({
    required this.id,
    required this.screeningCode,
    required this.childId,
    required this.historyReviewed,
    required this.currentConditionAssessed,
    required this.contraindicationsReviewed,
    required this.guardianConsentConfirmed,
    required this.outcome,
    required this.notes,
    required this.screenedAt,
    required this.screenedByUserId,
  });

  factory VaccinationScreening.fromJson(Map<String, dynamic> json) =>
      VaccinationScreening(
        id: json['id'] as String,
        screeningCode: json['screening_code'] as String,
        childId: json['child_id'] as String,
        historyReviewed: json['history_reviewed'] as bool,
        currentConditionAssessed: json['current_condition_assessed'] as bool,
        contraindicationsReviewed: json['contraindications_reviewed'] as bool,
        guardianConsentConfirmed: json['guardian_consent_confirmed'] as bool,
        outcome: VaccinationScreeningOutcome.values.byName(
          json['outcome'] as String,
        ),
        notes: json['notes'] as String? ?? '',
        screenedAt: DateTime.parse(json['screened_at'] as String),
        screenedByUserId: json['screened_by_user_id'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'screening_code': screeningCode,
    'child_id': childId,
    'history_reviewed': historyReviewed,
    'current_condition_assessed': currentConditionAssessed,
    'contraindications_reviewed': contraindicationsReviewed,
    'guardian_consent_confirmed': guardianConsentConfirmed,
    'outcome': outcome.name,
    'notes': notes,
    'screened_at': screenedAt.toIso8601String(),
    'screened_by_user_id': screenedByUserId,
  };
}
