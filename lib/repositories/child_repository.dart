import '../models/child_profile.dart';
import '../models/guardian_registration.dart';
import '../models/guardian_profile.dart';
import '../models/guardian_correction.dart';
import '../models/child_correction.dart';
import '../models/guardian_invitation.dart';
import '../models/child_link_request.dart';

class RegisteredFamily {
  final GuardianProfile guardian;
  final List<ChildProfile> children;
  final List<GuardianChildLink> links;
  final GuardianInvitation? invitation;

  const RegisteredFamily({
    required this.guardian,
    required this.children,
    required this.links,
    this.invitation,
  });
}

abstract class ChildRepository {
  Future<List<ChildProfile>> getChildrenForGuardian(String guardianId);

  Future<ChildProfile?> findChildByIdentifier(String identifier);

  Future<GuardianRegistrationResult> registerGuardianAndChild(
    GuardianRegistrationRequest request,
  );

  Future<List<RegisteredFamily>> getHealthWorkerRegisteredFamilies();

  Future<GuardianProfile?> findGuardianById(String guardianId);

  Future<ExistingGuardianChildResult> addChildToExistingGuardian(
    ExistingGuardianChildRequest request,
  );

  Future<List<ChildLinkRequest>> getGuardianChildLinkRequests(
    String guardianUserId,
  );

  Future<List<ChildLinkRequest>> getPendingChildLinkRequests();

  Future<ChildLinkRequest> submitChildLinkRequest(
    SubmitChildLinkRequest request,
  );

  Future<ChildLinkRequest> reviewChildLinkRequest({
    required String requestId,
    required bool approve,
    required String reviewedByUserId,
    required String reviewNotes,
  });

  Future<GuardianCorrectionResult> correctGuardian(
    GuardianCorrectionRequest request,
  );

  Future<ChildCorrectionResult> correctChild(ChildCorrectionRequest request);

  Future<GuardianProfile> activateGuardianInvitation({
    required String invitationCode,
    required String userId,
  });
}
