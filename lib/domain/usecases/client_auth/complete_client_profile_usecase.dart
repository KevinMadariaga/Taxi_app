import 'dart:io';

import 'package:taxi_app/domain/entities/client_user_entity.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';

class CompleteClientProfileParams {
  const CompleteClientProfileParams({
    required this.uid,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    this.profileImageFile,
  });

  final String uid;
  final String nombre;
  final String apellido;
  final String telefono;
  final File? profileImageFile;
}

class CompleteClientProfileUseCase {
  CompleteClientProfileUseCase(this._repository);

  final ClientAuthRepository _repository;

  Future<ClientUserEntity> call(CompleteClientProfileParams params) async {
    final existing = await _repository.getClientUserById(params.uid);

    String? fotoUrl = existing?.fotoUrl;
    if (params.profileImageFile != null) {
      fotoUrl = await _repository.uploadProfileImage(
        uid: params.uid,
        imageFile: params.profileImageFile!,
      );
    }

    await _repository.completeClientProfile(
      uid: params.uid,
      nombre: params.nombre,
      apellido: params.apellido,
      telefono: params.telefono,
      fotoUrl: fotoUrl,
    );

    final updated = await _repository.getClientUserById(params.uid);
    if (updated == null) {
      throw StateError('No fue posible cargar el perfil actualizado.');
    }

    return updated;
  }
}
