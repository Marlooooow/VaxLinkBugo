import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _client;

  SupabaseAuthRepository(this._client);

  @override
  Future<AppUser?> login({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) return null;

    try {
      final response = await _client.auth.signInWithPassword(
        email: _authenticationEmail(normalized),
        password: password,
      );
      return await _loadAppUser(response.user);
    } on AuthException {
      return null;
    }
  }

  @override
  Future<AppUser?> getCurrentUser() => _loadAppUser(_client.auth.currentUser);

  @override
  Future<void> logout() => _client.auth.signOut();

  @override
  Future<GuardianActivationResult> activateGuardianInvitation({
    required String activationCode,
  }) async {
    final result = await _client.functions.invoke(
      'activate-guardian-access',
      body: {'activation_code': activationCode.trim().toUpperCase()},
    );
    if (result.status < 200 ||
        result.status >= 300 ||
        result.data is! Map ||
        result.data['activated'] != true) {
      throw StateError('Guardian access could not be activated.');
    }

    final username = result.data['username'] as String?;
    final temporaryPassword = result.data['temporary_password'] as String?;
    if (username == null || temporaryPassword == null) {
      throw StateError('Activation completed without credentials.');
    }
    final user = await login(username: username, password: temporaryPassword);
    if (user == null) {
      throw StateError('Access was activated, but sign-in was unsuccessful.');
    }
    await logout();
    return GuardianActivationResult(
      user: user,
      username: username,
      temporaryPassword: temporaryPassword,
    );
  }

  @override
  Future<StaffActivationResult> activateStaffInvitation({
    required String activationCode,
  }) async {
    final result = await _client.functions.invoke(
      'activate-staff-access',
      body: {'activation_code': activationCode.trim().toUpperCase()},
    );
    if (result.status < 200 || result.status >= 300 || result.data is! Map) {
      final data = result.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Staff access could not be activated.';
      throw StateError(message);
    }
    final data = result.data as Map;
    if (data['activated'] != true) {
      throw StateError('Staff access could not be activated.');
    }
    final username = data['username'];
    final temporaryPassword = data['temporary_password'];
    if (username is! String ||
        username.isEmpty ||
        temporaryPassword is! String ||
        temporaryPassword.isEmpty) {
      throw StateError('Activation completed without login credentials.');
    }
    return StaffActivationResult(
      username: username,
      temporaryPassword: temporaryPassword,
    );
  }

  @override
  Future<void> changePassword(
    String newPassword, {
    String? currentPassword,
  }) async {
    if (newPassword.length < 8) {
      throw ArgumentError('Password must contain at least 8 characters.');
    }
    if (currentPassword != null) {
      final email = _client.auth.currentUser?.email;
      if (email == null || currentPassword.isEmpty) {
        throw StateError('Enter your current password.');
      }
      try {
        await _client.auth.signInWithPassword(
          email: email,
          password: currentPassword,
        );
      } on AuthException {
        throw StateError('The current password is incorrect.');
      }
    }
    final result = await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    if (result.user == null) throw StateError('Password could not be updated.');
    await _client.rpc('complete_password_change');
  }

  @override
  Future<bool> requestGuardianPasswordReset(String username) async {
    final result = await _client.rpc(
      'request_guardian_password_reset',
      params: {'requested_username': username.trim().toLowerCase()},
    );
    return result == true;
  }

  Future<AppUser?> _loadAppUser(User? authUser) async {
    if (authUser == null) return null;

    final row = await _client
        .from('profiles')
        .select('id, full_name, role, active, must_change_password')
        .eq('id', authUser.id)
        .maybeSingle();
    if (row == null ||
        row['active'] != true ||
        !['health_worker', 'administrator', 'guardian'].contains(row['role'])) {
      await _client.auth.signOut(scope: SignOutScope.local);
      return null;
    }

    return AppUser(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      role: row['role'] == 'health_worker' || row['role'] == 'administrator'
          ? UserRole.healthWorker
          : UserRole.guardian,
      active: row['active'] as bool? ?? false,
      isAdministrator: row['role'] == 'administrator',
      mustChangePassword: row['must_change_password'] as bool? ?? false,
    );
  }

  String _authenticationEmail(String username) =>
      username.contains('@') ? username : '$username@auth.vaxlink-bugo.local';
}
