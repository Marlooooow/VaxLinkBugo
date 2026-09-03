import '../models/staff_member.dart';

abstract class StaffRepository {
  Future<List<StaffMember>> getStaffMembers();
  Future<StaffInvitationResult> registerStaff(
    StaffRegistrationRequest request,
  );
}
