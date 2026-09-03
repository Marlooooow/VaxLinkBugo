import '../models/app_user.dart';

class GuardianActivationResult {
  final AppUser user;
  final String username;
  final String temporaryPassword;

  const GuardianActivationResult({
    required this.user,
    required this.username,
    required this.temporaryPassword,
  });
}

abstract class AuthRepository {
  Future<AppUser?> login({required String username, required String password});

  Future<AppUser?> getCurrentUser();
  Future<void> logout();

  Future<GuardianActivationResult> activateGuardianInvitation({
    required String activationCode,
  });

  Future<void> changePassword(String newPassword);

  Future<bool> requestGuardianPasswordReset(String username);
}
