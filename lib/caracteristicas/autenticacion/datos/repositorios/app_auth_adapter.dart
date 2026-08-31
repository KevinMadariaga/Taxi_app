import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/simple_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/client_auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/features/client/data/firebaseDB.dart';

/// Adapter that unifies legacy email/password `LegacyAuthRepository`
/// with the domain `ClientAuthRepository` implementation so we can
/// migrate progressively while keeping a single concrete instance.
class AppAuthAdapter extends LegacyAuthRepository
    implements ClientAuthRepository {
  AppAuthAdapter(
    FirebaseDataSource firebase, {
    ClientAuthRepository? clientRepo,
  }) : _clientRepo = clientRepo ?? ClientAuthRepositoryImpl(),
       super(firebase);

  final ClientAuthRepository _clientRepo;

  @override
  Future<AuthIdentityEntity?> signInWithGoogle() {
    return _clientRepo.signInWithGoogle();
  }

  @override
  Future<ClientUserEntity?> getClientUserById(String uid) {
    return _clientRepo.getClientUserById(uid);
  }

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
  }) {
    return _clientRepo.ensureClientUserForGoogle(
      uid: uid,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
    );
  }

  @override
  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  }) {
    return _clientRepo.uploadProfileImage(uid: uid, imageFile: imageFile);
  }

  @override
  Future<void> completeClientProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
    String? email,
  }) {
    return _clientRepo.completeClientProfile(
      uid: uid,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      fotoUrl: fotoUrl,
      email: email,
    );
  }

  @override
  Future<String> loginWithEmail({
    required String email,
    required String password,
  }) {
    // Reutiliza el login legado heredado de LegacyAuthRepository.
    return login(email, password);
  }

  @override
  Future<String> resolveUserRole(String uid) {
    return _clientRepo.resolveUserRole(uid);
  }

  @override
  Future<bool> isRegisteredAdmin(String uid) {
    return _clientRepo.isRegisteredAdmin(uid);
  }

  // logout() ya lo satisface el implementado heredado de LegacyAuthRepository.
}
