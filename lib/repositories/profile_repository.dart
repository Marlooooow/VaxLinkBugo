import '../models/account_profile.dart';
import '../models/app_user.dart';

abstract class ProfileRepository {
  Future<AccountProfile> getMyProfile(AppUser user);

  Future<AccountProfile> updateMyContact(
    AppUser user,
    ProfileContactUpdate update,
  );
}
