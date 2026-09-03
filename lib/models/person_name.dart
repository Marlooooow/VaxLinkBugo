class PersonName {
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;

  const PersonName({
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
  });

  String get fullName => [
    firstName.trim(),
    if (middleName?.trim().isNotEmpty == true) middleName!.trim(),
    lastName.trim(),
    if (suffix?.trim().isNotEmpty == true) suffix!.trim(),
  ].join(' ');

  Map<String, Object?> toJson() => {
    'first_name': firstName.trim(),
    'middle_name': _optional(middleName),
    'last_name': lastName.trim(),
    'suffix': _optional(suffix),
    'full_name': fullName,
  };

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
