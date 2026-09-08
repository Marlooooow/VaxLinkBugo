import 'app_user.dart';

class AccountProfile {
  final AppUser user;
  final String username;
  final String? accountCode;
  final String? facilityName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final DateTime? birthDate;
  final String? sex;
  final String? phone;
  final String? email;
  final String? address;
  final String? staffType;
  final String? licenseNumber;
  final String status;
  final List<AccountLinkedChild> linkedChildren;

  const AccountProfile({
    required this.user,
    required this.username,
    required this.accountCode,
    required this.facilityName,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.suffix,
    required this.birthDate,
    required this.sex,
    required this.phone,
    required this.email,
    required this.address,
    required this.staffType,
    required this.licenseNumber,
    required this.status,
    this.linkedChildren = const [],
  });

  bool get isGuardian => user.role == UserRole.guardian;
}

class AccountLinkedChild {
  final String id;
  final String name;
  final String childCode;
  final String relationship;

  const AccountLinkedChild({
    required this.id,
    required this.name,
    required this.childCode,
    required this.relationship,
  });
}

class ProfileContactUpdate {
  final String? phone;
  final String? email;
  final String? address;

  const ProfileContactUpdate({this.phone, this.email, this.address});
}
