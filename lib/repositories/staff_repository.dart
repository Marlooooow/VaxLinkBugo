import '../models/staff_member.dart';

abstract class StaffRepository {
  Future<List<StaffMember>> getStaffMembers();

  Future<StaffPage> getStaffMembersPage({
    String query = '',
    int limit = 20,
    int offset = 0,
  });
  Future<StaffInvitationResult> registerStaff(StaffRegistrationRequest request);

  Future<StaffMember> setStaffStatus(String staffId, StaffAccessStatus status);
}
