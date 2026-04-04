import 'package:taxi_app/core/auth/simple_auth_repository.dart';
import 'package:taxi_app/features/client/data/firebaseDB.dart';

/// Backwards-compatible wrapper so existing callsites can continue using
/// `AuthRepository(firebase)` while the centralized implementation lives in
/// `LegacyAuthRepository`.
class AuthRepository extends LegacyAuthRepository {
  AuthRepository(FirebaseDataSource firebase) : super(firebase);
}
