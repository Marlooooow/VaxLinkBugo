import 'referral.dart';

enum ReferralGroupStatus { pending, partiallyCompleted, completed }

class ReferralGroup {
  final String referralGroupId;
  final String referralGroupCode;
  final String verificationToken;
  final String childId;
  final String childName;
  final String originatingFacility;
  final DateTime issuedAt;
  final List<Referral> referrals;

  const ReferralGroup({
    required this.referralGroupId,
    required this.referralGroupCode,
    required this.verificationToken,
    required this.childId,
    required this.childName,
    required this.originatingFacility,
    required this.issuedAt,
    required this.referrals,
  });

  bool get isCompleted =>
      referrals.isNotEmpty && referrals.every((item) => item.isCompleted);

  bool get isPartiallyCompleted =>
      referrals.any((item) => item.isCompleted) && !isCompleted;

  ReferralGroupStatus get status => isCompleted
      ? ReferralGroupStatus.completed
      : isPartiallyCompleted
      ? ReferralGroupStatus.partiallyCompleted
      : ReferralGroupStatus.pending;

  List<Referral> get pendingReferrals =>
      referrals.where((item) => item.isPending).toList(growable: false);

  bool isOverdueOn(DateTime date) {
    final today = DateTime(date.year, date.month, date.day);
    return pendingReferrals.any((referral) {
      final due = referral.scheduledDueDate;
      final dueDate = DateTime(due.year, due.month, due.day);
      return dueDate.isBefore(today);
    });
  }

  ReferralGroup copyWith({List<Referral>? referrals}) {
    return ReferralGroup(
      referralGroupId: referralGroupId,
      referralGroupCode: referralGroupCode,
      verificationToken: verificationToken,
      childId: childId,
      childName: childName,
      originatingFacility: originatingFacility,
      issuedAt: issuedAt,
      referrals: referrals ?? this.referrals,
    );
  }

  factory ReferralGroup.fromJson(
    Map<String, dynamic> json, {
    List<Referral> referrals = const [],
  }) {
    return ReferralGroup(
      referralGroupId: json['referral_group_id'] as String,
      referralGroupCode: json['referral_group_code'] as String,
      verificationToken: json['verification_token'] as String,
      childId: json['child_id'] as String,
      childName: json['child_name'] as String,
      originatingFacility: json['originating_facility'] as String,
      issuedAt: DateTime.parse(json['issued_at'] as String),
      referrals: referrals,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'referral_group_id': referralGroupId,
      'referral_group_code': referralGroupCode,
      'verification_token': verificationToken,
      'child_id': childId,
      'child_name': childName,
      'originating_facility': originatingFacility,
      'issued_at': issuedAt.toIso8601String(),
    };
  }
}

class ReferralGroupSummaryCounts {
  final int pending;
  final int partiallyCompleted;
  final int completed;
  final int overdue;

  const ReferralGroupSummaryCounts({
    this.pending = 0,
    this.partiallyCompleted = 0,
    this.completed = 0,
    this.overdue = 0,
  });
}

class ReferralGroupPage {
  final List<ReferralGroup> items;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;
  final ReferralGroupSummaryCounts summary;

  const ReferralGroupPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
    required this.summary,
  });
}
