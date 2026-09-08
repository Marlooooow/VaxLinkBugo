import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_registration.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/guardian/guardian_invitation.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_link_request.dart';
import '../models/vaccination_schedule_state.dart';

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

class RegisteredFamilySummary {
  final RegisteredFamily family;
  final Map<String, VaccinationScheduleState> childStates;

  const RegisteredFamilySummary({
    required this.family,
    required this.childStates,
  });
}

class RegisteredFamilyPage {
  final List<RegisteredFamilySummary> items;
  final int totalCount;
  final bool hasMore;
  final DateTime? nextCreatedAt;
  final String? nextGuardianId;

  const RegisteredFamilyPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextCreatedAt,
    required this.nextGuardianId,
  });
}

abstract class ChildRepository {
  Future<List<ChildProfile>> getChildrenForGuardian(String guardianId);

  Future<ChildProfile?> findChildByIdentifier(String identifier);

  Future<GuardianRegistrationResult> registerGuardianAndChild(
    GuardianRegistrationRequest request,
  );

  Future<List<RegisteredFamily>> getHealthWorkerRegisteredFamilies();

  Future<RegisteredFamilyPage> getHealthWorkerRegisteredFamiliesPage({
    String search = '',
    VaccinationScheduleState? status,
    Set<String>? guardianIds,
    int pageSize = 20,
    DateTime? cursorCreatedAt,
    String? cursorGuardianId,
  });

  Future<RegisteredFamily?> getHealthWorkerRegisteredFamily(String guardianId);

  Future<GuardianProfile?> findGuardianById(String guardianId);

  Future<ExistingGuardianChildResult> addChildToExistingGuardian(
    ExistingGuardianChildRequest request,
  );

  Future<List<ChildLinkRequest>> getGuardianChildLinkRequests(
    String guardianUserId,
  );

  Future<List<ChildLinkRequest>> getPendingChildLinkRequests();

  Future<ChildLinkRequestPage> getPendingChildLinkRequestsPage({
    String query = '',
    String? initialRequestId,
    int limit = 20,
    int offset = 0,
  });

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
}
