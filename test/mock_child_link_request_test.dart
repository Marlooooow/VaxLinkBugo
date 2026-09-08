import 'package:flutter_test/flutter_test.dart';
import 'package:qr_code_based_pediatric_vaccination/models/child/child_link_request.dart';
import 'package:qr_code_based_pediatric_vaccination/repositories/mock_child_repository.dart';

void main() {
  test(
    'seeded guardian request is visible and links the child on approval',
    () async {
      final repository = MockChildRepository();

      final healthWorkerRequests = await repository
          .getPendingChildLinkRequests();
      final request = healthWorkerRequests.firstWhere(
        (item) => item.requestCode == 'CLR-2026-000001',
      );
      final guardianRequests = await repository.getGuardianChildLinkRequests(
        'USR-G-003',
      );

      expect(request.guardianName, 'Grace Villanueva');
      expect(request.childName, 'Lucas Villanueva');
      expect(request.status, ChildLinkRequestStatus.pending);
      expect(guardianRequests.map((item) => item.id), contains(request.id));

      final reviewed = await repository.reviewChildLinkRequest(
        requestId: request.id,
        approve: true,
        reviewedByUserId: 'USR-H-001',
        reviewNotes: 'Birth record and guardian relationship verified.',
      );
      final graceChildren = await repository.getChildrenForGuardian(
        'USR-G-003',
      );

      expect(reviewed.status, ChildLinkRequestStatus.approved);
      expect(reviewed.linkedChildId, isNotNull);
      expect(
        graceChildren.any(
          (child) =>
              child.id == reviewed.linkedChildId &&
              child.fullName == 'Lucas Villanueva',
        ),
        isTrue,
      );
    },
  );
}
