
import 'package:taxi_app/screens/usuario_cliente/data/firebaseDB.dart';

class AuthRepository {
  final FirebaseDataSource _firebase;

  AuthRepository(this._firebase);

  Future<void> login(String email, String password) {
    return _firebase.login(email, password);
  }

  Future<void> logout() {
    return _firebase.logout();
  }
}
