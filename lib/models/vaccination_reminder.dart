enum VaccinationReminderStatus {
  upcoming,
  dueToday,
  overdue,
  completed,
  dismissed,
}

enum VaccinationReminderChannel { inApp, sms, email, printedFollowUp }

class VaccinationReminder {
  bool get hasUnreadNotification =>
      !isRead &&
      status != VaccinationReminderStatus.completed &&
      status != VaccinationReminderStatus.dismissed;
  final String id;
  final String reminderCode;
  final String guardianId;
  final String childId;
  final String childName;
  final String vaccineId;
  final String vaccineName;
  final int doseNumber;
  final DateTime dueDate;
  final VaccinationReminderStatus status;
  final VaccinationReminderChannel channel;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VaccinationReminder({
    required this.id,
    required this.reminderCode,
    required this.guardianId,
    required this.childId,
    required this.childName,
    required this.vaccineId,
    required this.vaccineName,
    required this.doseNumber,
    required this.dueDate,
    required this.status,
    required this.channel,
    required this.isRead,
    required this.createdAt,
    required this.updatedAt,
  });

  VaccinationReminder copyWith({
    VaccinationReminderStatus? status,
    VaccinationReminderChannel? channel,
    bool? isRead,
    DateTime? updatedAt,
  }) => VaccinationReminder(
    id: id,
    reminderCode: reminderCode,
    guardianId: guardianId,
    childId: childId,
    childName: childName,
    vaccineId: vaccineId,
    vaccineName: vaccineName,
    doseNumber: doseNumber,
    dueDate: dueDate,
    status: status ?? this.status,
    channel: channel ?? this.channel,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory VaccinationReminder.fromJson(Map<String, dynamic> json) =>
      VaccinationReminder(
        id: json['id'] as String,
        reminderCode: json['reminder_code'] as String,
        guardianId: json['guardian_id'] as String,
        childId: json['child_id'] as String,
        childName: json['child_name'] as String,
        vaccineId: json['vaccine_id'] as String,
        vaccineName: json['vaccine_name'] as String,
        doseNumber: json['dose_number'] as int,
        dueDate: DateTime.parse(json['due_date'] as String),
        status: VaccinationReminderStatus.values.byName(
          json['status'] as String,
        ),
        channel: VaccinationReminderChannel.values.byName(
          json['channel'] as String,
        ),
        isRead: json['is_read'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'reminder_code': reminderCode,
    'guardian_id': guardianId,
    'child_id': childId,
    'child_name': childName,
    'vaccine_id': vaccineId,
    'vaccine_name': vaccineName,
    'dose_number': doseNumber,
    'due_date': dueDate.toIso8601String(),
    'status': status.name,
    'channel': channel.name,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class ReminderPreference {
  final String guardianId;
  final bool inAppEnabled;
  final bool smsEnabled;
  final bool emailEnabled;
  final int advanceNoticeDays;
  final DateTime updatedAt;

  const ReminderPreference({
    required this.guardianId,
    required this.inAppEnabled,
    required this.smsEnabled,
    required this.emailEnabled,
    required this.advanceNoticeDays,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'guardian_id': guardianId,
    'in_app_enabled': inAppEnabled,
    'sms_enabled': smsEnabled,
    'email_enabled': emailEnabled,
    'advance_notice_days': advanceNoticeDays,
    'updated_at': updatedAt.toIso8601String(),
  };
}
