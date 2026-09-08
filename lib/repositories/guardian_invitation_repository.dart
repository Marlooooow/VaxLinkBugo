import '../models/guardian/guardian_profile.dart';
import '../models/guardian/guardian_invitation.dart';

class GuardianInvitationIssueResult {
  final GuardianProfile guardian;
  final GuardianInvitation invitation;
  const GuardianInvitationIssueResult({
    required this.guardian,
    required this.invitation,
  });
}

abstract interface class GuardianInvitationIssuer {
  Future<GuardianInvitationIssueResult> issueGuardianInvitation(
    String guardianId,
  );
}
