enum ReminderFollowUpAction {
  mockSms,
  sms,
  assign,
  phoneCall,
  printedList,
  homeVisit,
}

enum ReminderFollowUpOutcome {
  reminderSent,
  providerAccepted,
  deliveryFailed,
  assigned,
  contacted,
  noAnswer,
  invalidContact,
  visitScheduled,
  declined,
  homeVisitRequired,
  printed,
}

class ReminderFollowUpRecord {
  final String id;
  final String followUpCode;
  final String reminderId;
  final String childId;
  final ReminderFollowUpAction action;
  final ReminderFollowUpOutcome outcome;
  final String? assignedToUserId;
  final String notes;
  final DateTime performedAt;
  final String performedByUserId;

  const ReminderFollowUpRecord({
    required this.id,
    required this.followUpCode,
    required this.reminderId,
    required this.childId,
    required this.action,
    required this.outcome,
    required this.assignedToUserId,
    required this.notes,
    required this.performedAt,
    required this.performedByUserId,
  });

  factory ReminderFollowUpRecord.fromJson(Map<String, dynamic> json) =>
      ReminderFollowUpRecord(
        id: json['id'] as String,
        followUpCode: json['follow_up_code'] as String,
        reminderId: json['reminder_id'] as String,
        childId: json['child_id'] as String,
        action: ReminderFollowUpAction.values.byName(json['action'] as String),
        outcome: ReminderFollowUpOutcome.values.byName(
          json['outcome'] as String,
        ),
        assignedToUserId: json['assigned_to_user_id'] as String?,
        notes: json['notes'] as String? ?? '',
        performedAt: DateTime.parse(json['performed_at'] as String),
        performedByUserId: json['performed_by_user_id'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'follow_up_code': followUpCode,
    'reminder_id': reminderId,
    'child_id': childId,
    'action': action.name,
    'outcome': outcome.name,
    'assigned_to_user_id': assignedToUserId,
    'notes': notes,
    'performed_at': performedAt.toIso8601String(),
    'performed_by_user_id': performedByUserId,
  };
}

class ReminderBatchActionRequest {
  final List<String> reminderIds;
  final ReminderFollowUpAction action;
  final ReminderFollowUpOutcome outcome;
  final String? assignedToUserId;
  final String notes;
  final String performedByUserId;

  const ReminderBatchActionRequest({
    required this.reminderIds,
    required this.action,
    required this.outcome,
    required this.assignedToUserId,
    required this.notes,
    required this.performedByUserId,
  });
}
