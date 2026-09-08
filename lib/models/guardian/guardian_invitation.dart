enum GuardianInvitationChannel { sms, email, printedSlip }

enum GuardianInvitationStatus {
  pendingDelivery,
  delivered,
  failed,
  accepted,
  expired,
  revoked,
}

class GuardianInvitation {
  final String id;
  final String invitationCode;
  final String guardianId;
  final GuardianInvitationChannel channel;
  final String destination;
  final String maskedDestination;
  final GuardianInvitationStatus status;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final String createdByUserId;

  const GuardianInvitation({
    required this.id,
    required this.invitationCode,
    required this.guardianId,
    required this.channel,
    required this.destination,
    required this.maskedDestination,
    required this.status,
    required this.createdAt,
    required this.deliveredAt,
    required this.expiresAt,
    required this.acceptedAt,
    required this.createdByUserId,
  });

  String get channelLabel => switch (channel) {
    GuardianInvitationChannel.sms => 'SMS',
    GuardianInvitationChannel.email => 'Email',
    GuardianInvitationChannel.printedSlip => 'Printed code / manual handoff',
  };

  String get statusLabel => switch (status) {
    GuardianInvitationStatus.pendingDelivery =>
      channel == GuardianInvitationChannel.printedSlip
          ? 'Awaiting activation'
          : 'Awaiting delivery',
    GuardianInvitationStatus.delivered => 'Delivered',
    GuardianInvitationStatus.failed => 'Delivery failed',
    GuardianInvitationStatus.accepted => 'Activated',
    GuardianInvitationStatus.expired => 'Expired',
    GuardianInvitationStatus.revoked => 'Revoked',
  };

  GuardianInvitation copyWith({
    GuardianInvitationStatus? status,
    DateTime? deliveredAt,
    DateTime? acceptedAt,
  }) => GuardianInvitation(
    id: id,
    invitationCode: invitationCode,
    guardianId: guardianId,
    channel: channel,
    destination: destination,
    maskedDestination: maskedDestination,
    status: status ?? this.status,
    createdAt: createdAt,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    expiresAt: expiresAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    createdByUserId: createdByUserId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'invitation_code': invitationCode,
    'guardian_id': guardianId,
    'channel': channel.name,
    'destination': destination,
    'masked_destination': maskedDestination,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'delivered_at': deliveredAt?.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'accepted_at': acceptedAt?.toIso8601String(),
    'created_by_user_id': createdByUserId,
  };
}
