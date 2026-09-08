import '../models/app_user.dart';
import 'auth_repository.dart';
import 'demo_repository.dart';
import 'mock_child_repository.dart';
import '../services/mock_identifier_generator.dart';

class MockAuthRepository implements AuthRepository, DemoRepository {
  AppUser? _currentUser;

  static const List<_MockAccount> _prototypeAccounts = [
    _MockAccount(
      username: 'guardian',
      password: 'guardian123',
      user: AppUser(
        id: 'USR-G-001',
        fullName: 'Maria Santos',
        role: UserRole.guardian,
        active: true,
      ),
    ),
    _MockAccount(
      username: 'paolo.guardian',
      password: 'guardian123',
      user: AppUser(
        id: 'USR-G-002',
        fullName: 'Paolo Mendoza',
        role: UserRole.guardian,
        active: true,
      ),
    ),
    _MockAccount(
      username: 'grace.guardian',
      password: 'guardian123',
      user: AppUser(
        id: 'USR-G-003',
        fullName: 'Grace Villanueva',
        role: UserRole.guardian,
        active: true,
      ),
    ),
    _MockAccount(
      username: 'admin',
      password: 'admin123',
      user: AppUser(
        id: 'USR-A-001',
        fullName: 'Barangay Health Administrator',
        role: UserRole.healthWorker,
        active: true,
        isAdministrator: true,
      ),
    ),
    _MockAccount(
      username: 'healthworker',
      password: 'health123',
      user: AppUser(
        id: 'USR-H-001',
        fullName: 'Nurse Maria Reyes',
        role: UserRole.healthWorker,
        active: true,
      ),
    ),
  ];
  final List<_MockAccount> _accounts = List.of(_prototypeAccounts);

  void _ensurePrototypeAccounts() {
    for (final seed in _prototypeAccounts) {
      final exists = _accounts.any(
        (account) =>
            account.username.toLowerCase() == seed.username.toLowerCase(),
      );
      if (!exists) _accounts.add(seed);
    }
  }

  @override
  Future<AppUser?> login({
    required String username,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    _ensurePrototypeAccounts();
    final normalizedUsername = username.trim().toLowerCase();

    for (final account in _accounts) {
      if (account.username.toLowerCase() == normalizedUsername &&
          account.password == password) {
        _currentUser = account.user;
        return _currentUser;
      }
    }
    return null;
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _currentUser;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = null;
  }

  @override
  Future<GuardianActivationResult> activateGuardianInvitation({
    required String activationCode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 550));
    _ensurePrototypeAccounts();
    final identity = MockIdentifierGenerator.next(prefix: 'USR');
    final guardian = await MockChildRepository().activateGuardianInvitation(
      invitationCode: activationCode,
      userId: identity.id,
    );
    final normalizedUsername = guardian.guardianCode.toLowerCase();
    final password = _temporaryPassword(guardian.lastName, guardian.firstName);
    if (_accounts.any(
      (account) => account.username.toLowerCase() == normalizedUsername,
    )) {
      throw StateError('That username is already in use.');
    }
    final user = AppUser(
      id: identity.id,
      fullName: guardian.fullName,
      role: UserRole.guardian,
      active: true,
    );
    _accounts.add(
      _MockAccount(
        username: normalizedUsername,
        password: password,
        user: user,
      ),
    );
    return GuardianActivationResult(
      user: user,
      username: normalizedUsername,
      temporaryPassword: password,
    );
  }

  @override
  Future<StaffActivationResult> activateStaffInvitation({
    required String activationCode,
  }) async {
    throw StateError('Staff activation is available only in live mode.');
  }

  @override
  Future<void> changePassword(
    String newPassword, {
    String? currentPassword,
  }) async {}

  @override
  Future<bool> requestGuardianPasswordReset(String username) async => _accounts
      .any((account) => account.username == username.trim().toLowerCase());

  String _temporaryPassword(String? lastName, String? firstName) {
    final value = '${lastName ?? ''}_${firstName ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return value.length >= 8 ? value : '${value}123';
  }
}

class _MockAccount {
  final String username;
  final String password;
  final AppUser user;

  const _MockAccount({
    required this.username,
    required this.password,
    required this.user,
  });
}
