import 'package:taxi_app/domain/entities/client_user_entity.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';

class GetClientUserUseCase {
  GetClientUserUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<ClientUserEntity?> call(String uid) {
    return _repository.getClientUserById(uid);
  }
}
