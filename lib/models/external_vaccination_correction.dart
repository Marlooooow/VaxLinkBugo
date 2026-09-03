class ExternalVaccinationCorrection {
  final String correctionId;
  final String correctionCode;
  final String externalVisitId;
  final String reason;
  final Map<String, dynamic> previousValues;
  final Map<String, dynamic> updatedValues;
  final DateTime correctedAt;
  final String? correctedBy;

  const ExternalVaccinationCorrection({
    required this.correctionId,
    required this.correctionCode,
    required this.externalVisitId,
    required this.reason,
    required this.previousValues,
    required this.updatedValues,
    required this.correctedAt,
    this.correctedBy,
  });

  factory ExternalVaccinationCorrection.fromJson(Map<String, dynamic> json) {
    return ExternalVaccinationCorrection(
      correctionId: json['correction_id'] as String,
      correctionCode: json['correction_code'] as String,
      externalVisitId: json['external_visit_id'] as String,
      reason: json['reason'] as String,
      previousValues: Map<String, dynamic>.from(json['previous_values'] as Map),
      updatedValues: Map<String, dynamic>.from(json['updated_values'] as Map),
      correctedAt: DateTime.parse(json['corrected_at'] as String),
      correctedBy: json['corrected_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'correction_id': correctionId,
      'correction_code': correctionCode,
      'external_visit_id': externalVisitId,
      'reason': reason,
      'previous_values': previousValues,
      'updated_values': updatedValues,
      'corrected_at': correctedAt.toIso8601String(),
      'corrected_by': correctedBy,
    };
  }
}
