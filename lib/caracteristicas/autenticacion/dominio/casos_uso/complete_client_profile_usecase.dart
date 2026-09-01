import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class CompleteClientProfileParams {
  const CompleteClientProfileParams({
    required this.uid,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    this.profileImageFile,
    this.email,
  });

  final String uid;
  final String nombre;
  final String apellido;
  final String telefono;
  final File? profileImageFile;
  final String? email;
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

    // Guarda de última línea: `complete_profile_controller.dart` ya valida
    // que haya foto nueva o previa antes de llamar acá, pero ese chequeo
    // vive en la UI. Este usecase es el único punto real de escritura de
    // `isProfileComplete: true` — sin este guard, cualquier caller futuro
    // (o un `existing.fotoUrl` que resultara vacío por datos legacy) podría
    // marcar el perfil completo con la foto en blanco.
    if ((fotoUrl ?? '').trim().isEmpty) {
      throw StateError('Toma una foto de perfil para continuar.');
    }

    await _repository.completeClientProfile(
      uid: params.uid,
      nombre: params.nombre,
      apellido: params.apellido,
      telefono: params.telefono,
      fotoUrl: fotoUrl,
      email: params.email,
    );

    // Igual que en el sign-in: sincroniza `displayName` de Auth con el
    // nombre recién guardado, para que ningún lector caiga en el nombre
    // viejo del proveedor.
    await _repository.syncAuthDisplayName(
      '${params.nombre} ${params.apellido}'.trim(),
    );

    final updated = await _repository.getClientUserById(params.uid);
    if (updated == null) {
      throw StateError('No fue posible cargar el perfil actualizado.');
    }

    return updated;
  }
}
