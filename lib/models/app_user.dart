enum UserRole { guardian, healthWorker }

class AppUser {
  final String id;
  final String fullName;
  final UserRole role;
  final bool active;
  final bool isAdministrator;
  final bool mustChangePassword;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.active,
    this.isAdministrator = false,
    this.mustChangePassword = false,
  });
}
