import '../models/staff_member.dart';
import 'staff_repository.dart';

class UnavailableStaffRepository implements StaffRepository {
  const UnavailableStaffRepository();

  @override
  Future<List<StaffMember>> getStaffMembers() async => const [];

  @override
  Future<StaffPage> getStaffMembersPage({
    String query = '',
    int limit = 20,
    int offset = 0,
  }) async =>
      const StaffPage(items: [], totalCount: 0, hasMore: false, nextOffset: 0);

  @override
  Future<StaffInvitationResult> registerStaff(
    StaffRegistrationRequest request,
  ) => throw StateError('Staff administration requires the live database.');

  @override
  Future<StaffMember> setStaffStatus(
    String staffId,
    StaffAccessStatus status,
  ) => throw StateError('Staff administration requires the live database.');
}
