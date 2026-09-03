import '../models/app_user.dart';

class SessionContext {
  SessionContext._();

  static AppUser? _user;

  static AppUser? get user => _user;
  static String get userId {
    final active = _user;
    if (active == null) {
      throw StateError('A signed-in user is required for this action.');
    }
    return active.id;
  }

  static void setUser(AppUser user) => _user = user;
  static void clear() => _user = null;
}
