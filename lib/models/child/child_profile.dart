class ChildProfile {
  final String id;
  final String fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final DateTime birthDate;
  final String sex;
  final String qrIdentifier;
  final String relationship;

  const ChildProfile({
    required this.id,
    required this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    required this.birthDate,
    required this.sex,
    required this.qrIdentifier,
    required this.relationship,
  });

  ChildProfile copyWith({
    String? fullName,
    DateTime? birthDate,
    String? sex,
    String? relationship,
  }) => ChildProfile(
    id: id,
    fullName: fullName ?? this.fullName,
    firstName: firstName,
    middleName: middleName,
    lastName: lastName,
    suffix: suffix,
    birthDate: birthDate ?? this.birthDate,
    sex: sex ?? this.sex,
    qrIdentifier: qrIdentifier,
    relationship: relationship ?? this.relationship,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'full_name': fullName,
    'first_name': firstName,
    'middle_name': middleName,
    'last_name': lastName,
    'suffix': suffix,
    'birth_date': birthDate.toIso8601String(),
    'sex': sex,
    'qr_identifier': qrIdentifier,
    'relationship': relationship,
  };

  int get ageInMonths {
    final now = DateTime.now();

    return (now.year - birthDate.year) * 12 +
        now.month -
        birthDate.month -
        (now.day < birthDate.day ? 1 : 0);
  }

  bool get isParentRelationship {
    final normalized = relationship.trim().toLowerCase();
    return normalized == 'mother' || normalized == 'father';
  }
}
