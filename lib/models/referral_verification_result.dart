import 'referral_group.dart';

enum ReferralVerificationStatus {
  valid,
  notFound,
  invalidToken,
  cancelled,
  completed,
}

class ReferralVerificationResult {
  final ReferralVerificationStatus status;
  final ReferralGroup? referralGroup;
  final String message;

  const ReferralVerificationResult({
    required this.status,
    required this.message,
    this.referralGroup,
  });

  bool get canContinue => status == ReferralVerificationStatus.valid;
}
