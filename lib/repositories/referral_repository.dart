import '../models/child/child_profile.dart';
import '../models/external_vaccination/external_vaccination_record.dart';
import '../models/external_vaccination/external_vaccination_correction.dart';
import '../models/external_vaccination/external_vaccination_visit.dart';
import '../models/referral.dart';
import '../models/referral_group.dart';
import '../models/referral_verification_result.dart';
import '../models/vaccine_inventory.dart';

abstract class ReferralRepository {
  Future<Referral> createReferral({
    required ChildProfile child,
    required VaccineInventory vaccine,
  });

  Future<List<Referral>> createReferralGroup({
    required ChildProfile child,
    required List<VaccineInventory> vaccines,
  });

  Future<Referral?> getReferralById(String referralId);

  Future<Referral?> simulateReferralScan();

  Future<List<Referral>> getReferralGroupByReferralId(String referralId);

  Future<List<Referral>> simulateReferralGroupScan();

  Future<Referral> recordExternalVaccination({
    required Referral referral,
    required ExternalVaccinationRecord record,
  });

  Future<List<Referral>> recordExternalVaccinationBatch({
    required List<Referral> referrals,
    required List<ExternalVaccinationRecord> records,
  });

  Future<ExternalVaccinationRecord?> getExternalVaccinationRecord(
    String referralId,
  );

  Future<ExternalVaccinationRecord> updateExternalVaccination({
    required ExternalVaccinationRecord record,
    required String correctionReason,
  });

  Future<ReferralGroup?> getReferralGroup(String referralGroupId);

  Future<List<ReferralGroup>> getReferralGroups({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  });

  Future<ReferralGroupPage> getReferralGroupsPage({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  });

  Future<ReferralVerificationResult> verifyReferralGroup({
    required String referralGroupId,
    String? verificationToken,
  });

  Future<ExternalVaccinationVisit?> getExternalVaccinationVisitByReferralId(
    String referralId,
  );

  Future<List<ExternalVaccinationCorrection>> getVisitCorrections(
    String externalVisitId,
  );
}
