import 'package:qr_code_based_pediatric_vaccination/models/child/child_profile.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_record.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_correction.dart';
import 'package:qr_code_based_pediatric_vaccination/models/external_vaccination/external_vaccination_visit.dart';
import '../models/referral.dart';
import '../models/referral_group.dart';
import '../models/referral_verification_result.dart';
import '../models/vaccine_inventory.dart';
import 'referral_repository.dart';
import 'live_data_access.dart';

/// Intentionally unavailable, rather than minting prototype verification tokens
/// for real patients. Replace with the verified, transactional referral adapter.
class PendingLiveReferralRepository implements ReferralRepository {
  const PendingLiveReferralRepository();
  Never _pending() =>
      throw const LiveOperationUnavailable('Referral processing');
  @override
  Future<Referral> createReferral({
    required ChildProfile child,
    required VaccineInventory vaccine,
  }) async => _pending();
  @override
  Future<List<Referral>> createReferralGroup({
    required ChildProfile child,
    required List<VaccineInventory> vaccines,
  }) async => _pending();
  @override
  Future<Referral?> getReferralById(String referralId) async => _pending();
  @override
  Future<Referral?> simulateReferralScan() async => _pending();
  @override
  Future<List<Referral>> getReferralGroupByReferralId(
    String referralId,
  ) async => _pending();
  @override
  Future<List<Referral>> simulateReferralGroupScan() async => _pending();
  @override
  Future<Referral> recordExternalVaccination({
    required Referral referral,
    required ExternalVaccinationRecord record,
  }) async => _pending();
  @override
  Future<List<Referral>> recordExternalVaccinationBatch({
    required List<Referral> referrals,
    required List<ExternalVaccinationRecord> records,
  }) async => _pending();
  @override
  Future<ExternalVaccinationRecord?> getExternalVaccinationRecord(
    String referralId,
  ) async => _pending();
  @override
  Future<ExternalVaccinationRecord> updateExternalVaccination({
    required ExternalVaccinationRecord record,
    required String correctionReason,
  }) async => _pending();
  @override
  Future<ReferralGroup?> getReferralGroup(String referralGroupId) async =>
      _pending();
  @override
  Future<List<ReferralGroup>> getReferralGroups({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  }) async => _pending();
  @override
  Future<ReferralGroupPage> getReferralGroupsPage({
    String query = '',
    ReferralGroupStatus? status,
    bool overdueOnly = false,
    int limit = 20,
    int offset = 0,
  }) async => _pending();
  @override
  Future<ReferralVerificationResult> verifyReferralGroup({
    required String referralGroupId,
    String? verificationToken,
  }) async => _pending();
  @override
  Future<ExternalVaccinationVisit?> getExternalVaccinationVisitByReferralId(
    String referralId,
  ) async => _pending();
  @override
  Future<List<ExternalVaccinationCorrection>> getVisitCorrections(
    String externalVisitId,
  ) async => _pending();
}
