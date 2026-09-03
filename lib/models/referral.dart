class Referral {
  final String id;
  final String referralCode;
  final String referralGroupId;
  final String referralGroupCode;
  final String childId;
  final String childName;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime scheduledDueDate;
  final String originatingFacility;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? verificationToken;

  const Referral({
    required this.id,
    required this.referralCode,
    required this.referralGroupId,
    required this.referralGroupCode,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.scheduledDueDate,
    required this.originatingFacility,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.verificationToken,
  });

  bool get isPending => status == 'Pending';

  bool get isCompleted => status == 'Completed';

  String get referralId => referralCode;

  factory Referral.fromJson(Map<String, dynamic> json) {
    return Referral(
      id: json['id'] as String,
      referralCode: json['referral_code'] as String,
      referralGroupId: json['referral_group_id'] as String,
      referralGroupCode: json['referral_group_code'] as String,
      childId: json['child_id'] as String,
      childName: json['child_name'] as String,
      vaccineId: json['vaccine_id'] as String,
      vaccineName: json['vaccine_name'] as String,
      doseNumber: json['dose_number'] as int,
      scheduledDueDate: DateTime.parse(json['scheduled_due_date'] as String),
      originatingFacility: json['originating_facility'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      verificationToken: json['verification_token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'referral_code': referralCode,
      'referral_group_id': referralGroupId,
      'referral_group_code': referralGroupCode,
      'child_id': childId,
      'child_name': childName,
      'vaccine_id': vaccineId,
      'vaccine_name': vaccineName,
      'dose_number': doseNumber,
      'scheduled_due_date': scheduledDueDate.toIso8601String(),
      'originating_facility': originatingFacility,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'verification_token': verificationToken,
    };
  }

  Referral copyWith({String? status, DateTime? completedAt}) {
    return Referral(
      id: id,
      referralCode: referralCode,
      referralGroupId: referralGroupId,
      referralGroupCode: referralGroupCode,
      childId: childId,
      childName: childName,
      vaccineId: vaccineId,
      vaccineName: vaccineName,
      doseNumber: doseNumber,
      scheduledDueDate: scheduledDueDate,
      originatingFacility: originatingFacility,
      status: status ?? this.status,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
      verificationToken: verificationToken,
    );
  }
}
