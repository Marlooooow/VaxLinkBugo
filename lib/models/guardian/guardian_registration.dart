import '../child/child_profile.dart';
import 'guardian_profile.dart';
import 'guardian_invitation.dart';
import '../person_name.dart';

class GuardianRegistrationRequest {
  final String guardianName;
  final String? guardianFirstName;
  final String? guardianMiddleName;
  final String? guardianLastName;
  final String? guardianSuffix;
  final DateTime? guardianBirthDate;
  final String guardianSex;
  final String? phoneNumber;
  final String? emailAddress;
  final String address;
  final bool createUserAccount;
  final GuardianInvitationChannel? invitationChannel;
  final List<ChildRegistrationInput> children;
  final bool authorizationConfirmed;
  final String registeredByUserId;

  const GuardianRegistrationRequest({
    required this.guardianName,
    this.guardianFirstName,
    this.guardianMiddleName,
    this.guardianLastName,
    this.guardianSuffix,
    this.guardianBirthDate,
    this.guardianSex = 'Female',
    required this.phoneNumber,
    required this.emailAddress,
    required this.address,
    required this.createUserAccount,
    required this.invitationChannel,
    required this.children,
    required this.authorizationConfirmed,
    required this.registeredByUserId,
  });

  factory GuardianRegistrationRequest.structured({
    required PersonName guardianName,
    required DateTime guardianBirthDate,
    String guardianSex = 'Female',
    required String? phoneNumber,
    required String? emailAddress,
    required String address,
    required bool createUserAccount,
    required GuardianInvitationChannel? invitationChannel,
    required List<ChildRegistrationInput> children,
    required bool authorizationConfirmed,
    required String registeredByUserId,
  }) => GuardianRegistrationRequest(
    guardianName: guardianName.fullName,
    guardianFirstName: guardianName.firstName,
    guardianMiddleName: guardianName.middleName,
    guardianLastName: guardianName.lastName,
    guardianSuffix: guardianName.suffix,
    guardianBirthDate: guardianBirthDate,
    guardianSex: guardianSex,
    phoneNumber: phoneNumber,
    emailAddress: emailAddress,
    address: address,
    createUserAccount: createUserAccount,
    invitationChannel: invitationChannel,
    children: children,
    authorizationConfirmed: authorizationConfirmed,
    registeredByUserId: registeredByUserId,
  );
}

class ChildRegistrationInput {
  final String fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? suffix;
  final DateTime birthDate;
  final String sex;
  final String relationship;

  const ChildRegistrationInput({
    required this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.suffix,
    required this.birthDate,
    required this.sex,
    required this.relationship,
  });

  factory ChildRegistrationInput.structured({
    required PersonName name,
    required DateTime birthDate,
    required String sex,
    required String relationship,
  }) => ChildRegistrationInput(
    fullName: name.fullName,
    firstName: name.firstName,
    middleName: name.middleName,
    lastName: name.lastName,
    suffix: name.suffix,
    birthDate: birthDate,
    sex: sex,
    relationship: relationship,
  );
}

class GuardianRegistrationResult {
  final GuardianProfile guardian;
  final List<ChildProfile> children;
  final List<GuardianChildLink> links;
  final GuardianInvitation? invitation;

  const GuardianRegistrationResult({
    required this.guardian,
    required this.children,
    required this.links,
    required this.invitation,
  });

  ChildProfile get child => children.first;
  GuardianChildLink get link => links.first;
}

class ExistingGuardianChildRequest {
  final String guardianId;
  final ChildRegistrationInput child;
  final bool authorizationConfirmed;
  final String registeredByUserId;

  const ExistingGuardianChildRequest({
    required this.guardianId,
    required this.child,
    required this.authorizationConfirmed,
    required this.registeredByUserId,
  });
}

class ExistingGuardianChildResult {
  final ChildProfile child;
  final GuardianChildLink link;

  const ExistingGuardianChildResult({required this.child, required this.link});
}
