import 'package:taxi_app/features/client/data/firebaseDB.dart';

/// Thin adapter that preserves the legacy email/password `AuthRepository` API
/// used across the app (login/logout) while centralizing the code.
class LegacyAuthRepository {
  final FirebaseDataSource _firebase;

  LegacyAuthRepository(this._firebase);

  Future<String> login(String email, String password) {
    return _firebase.login(email, password);
  }

  Future<void> logout() {
    return _firebase.logout();
  }
}
