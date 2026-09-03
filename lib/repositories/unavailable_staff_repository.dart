import '../models/staff_member.dart';
import 'staff_repository.dart';

class UnavailableStaffRepository implements StaffRepository {
  const UnavailableStaffRepository();

  @override
  Future<List<StaffMember>> getStaffMembers() async => const [];

  @override
  Future<StaffInvitationResult> registerStaff(
    StaffRegistrationRequest request,
  ) => throw StateError('Staff administration requires the live database.');
}
