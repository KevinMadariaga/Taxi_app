import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class GetClientUserUseCase {
  GetClientUserUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<ClientUserEntity?> call(String uid) {
    return _repository.getClientUserById(uid);
  }
}
