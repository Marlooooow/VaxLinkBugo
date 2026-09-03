enum StaffNotificationTarget {
  requests,
  inventory,
  appointments,
  offers,
  waitlist,
  followUps,
  insights,
  passwordResets,
}

class StaffNotification {
  final String id;
  final String title;
  final String body;
  final StaffNotificationTarget target;
  final String? entityId;
  final DateTime createdAt;

  const StaffNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    required this.createdAt,
    this.entityId,
  });

  /// The same payload contract applies to mock, database and push sources.
  /// Targets are allowlisted; titles and message text never control navigation.
  factory StaffNotification.fromJson(Map<String, dynamic> json) {
    String requiredText(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Missing notification field: $key');
      }
      return value;
    }

    final targetName = requiredText('target');
    final matches = StaffNotificationTarget.values.where(
      (t) => t.name == targetName,
    );
    if (matches.isEmpty) {
      throw const FormatException('Unsupported notification target.');
    }
    final target = matches.first;
    final rawEntityId = json['entity_id'];
    if (rawEntityId != null && rawEntityId is! String) {
      throw const FormatException('Invalid notification record identifier.');
    }
    final entityId = (rawEntityId as String?)?.trim();
    if (target != StaffNotificationTarget.followUps &&
        (entityId == null || entityId.isEmpty)) {
      throw const FormatException(
        'A record identifier is required for this notification.',
      );
    }
    return StaffNotification(
      id: requiredText('id'),
      title: requiredText('title'),
      body: requiredText('body'),
      target: target,
      entityId: entityId,
      createdAt: DateTime.parse(requiredText('created_at')),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'target': target.name,
    'entity_id': entityId,
    'created_at': createdAt.toIso8601String(),
  };
}
