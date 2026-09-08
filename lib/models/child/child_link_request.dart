import '../person_name.dart';

enum ChildLinkRequestStatus { pending, approved, rejected, merged }

class ChildLinkRequest {
  final String id;
  final String requestCode;
  final String guardianId;
  final String guardianName;
  final String childName;
  final String? childFirstName;
  final String? childMiddleName;
  final String? childLastName;
  final String? childSuffix;
  final DateTime birthDate;
  final String sex;
  final String relationship;
  final ChildLinkRequestStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedByUserId;
  final String? reviewNotes;
  final String? linkedChildId;

  const ChildLinkRequest({
    required this.id,
    required this.requestCode,
    required this.guardianId,
    required this.guardianName,
    required this.childName,
    this.childFirstName,
    this.childMiddleName,
    this.childLastName,
    this.childSuffix,
    required this.birthDate,
    required this.sex,
    required this.relationship,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedByUserId,
    this.reviewNotes,
    this.linkedChildId,
  });

  ChildLinkRequest copyWith({
    ChildLinkRequestStatus? status,
    DateTime? reviewedAt,
    String? reviewedByUserId,
    String? reviewNotes,
    String? linkedChildId,
  }) => ChildLinkRequest(
    id: id,
    requestCode: requestCode,
    guardianId: guardianId,
    guardianName: guardianName,
    childName: childName,
    childFirstName: childFirstName,
    childMiddleName: childMiddleName,
    childLastName: childLastName,
    childSuffix: childSuffix,
    birthDate: birthDate,
    sex: sex,
    relationship: relationship,
    status: status ?? this.status,
    submittedAt: submittedAt,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewedByUserId: reviewedByUserId ?? this.reviewedByUserId,
    reviewNotes: reviewNotes ?? this.reviewNotes,
    linkedChildId: linkedChildId ?? this.linkedChildId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'request_code': requestCode,
    'guardian_id': guardianId,
    'guardian_name': guardianName,
    'child_name': childName,
    'first_name': childFirstName,
    'middle_name': childMiddleName,
    'last_name': childLastName,
    'suffix': childSuffix,
    'birth_date': birthDate.toIso8601String(),
    'sex': sex,
    'relationship': relationship,
    'status': status.name,
    'submitted_at': submittedAt.toIso8601String(),
    'reviewed_at': reviewedAt?.toIso8601String(),
    'reviewed_by_user_id': reviewedByUserId,
    'review_notes': reviewNotes,
    'linked_child_id': linkedChildId,
  };
}

class ChildLinkRequestPage {
  final List<ChildLinkRequest> items;
  final int totalCount;
  final bool hasMore;
  final int nextOffset;

  const ChildLinkRequestPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    required this.nextOffset,
  });
}

class SubmitChildLinkRequest {
  final String guardianUserId;
  final String childName;
  final String? childFirstName;
  final String? childMiddleName;
  final String? childLastName;
  final String? childSuffix;
  final DateTime birthDate;
  final String sex;
  final String relationship;

  const SubmitChildLinkRequest({
    required this.guardianUserId,
    required this.childName,
    this.childFirstName,
    this.childMiddleName,
    this.childLastName,
    this.childSuffix,
    required this.birthDate,
    required this.sex,
    required this.relationship,
  });

  factory SubmitChildLinkRequest.structured({
    required String guardianUserId,
    required PersonName childName,
    required DateTime birthDate,
    required String sex,
    required String relationship,
  }) => SubmitChildLinkRequest(
    guardianUserId: guardianUserId,
    childName: childName.fullName,
    childFirstName: childName.firstName,
    childMiddleName: childName.middleName,
    childLastName: childName.lastName,
    childSuffix: childName.suffix,
    birthDate: birthDate,
    sex: sex,
    relationship: relationship,
  );
}
