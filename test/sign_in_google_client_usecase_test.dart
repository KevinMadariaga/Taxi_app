import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

/// Cubre el candado de este fix: el nombre guardado en Firestore
/// (`usuarios/{uid}.nombre`) debe mandar sobre el `displayName` que trae el
/// login de Google — nunca al revés. `ensureClientUserForGoogle` ya protege
/// la escritura en Firestore (ver `ensure_for_google_datasource_test.dart`);
/// este test cubre el paso siguiente: que el usecase sincronice
/// `FirebaseAuth.displayName` con el nombre YA guardado (`user.nombre`), no
/// con el que trajo el proveedor.
class _FakeClientAuthRepository implements ClientAuthRepository {
  _FakeClientAuthRepository({required this.usuarioExistente});

  final ClientUserEntity usuarioExistente;
  String? nombreSincronizadoEnAuth;

  @override
  Future<AuthIdentityEntity?> signInWithGoogle() async {
    return const AuthIdentityEntity(
      uid: 'u1',
      displayName: 'Gmail Default',
      email: 'gmail-default@example.com',
    );
  }

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
  }) async {
    // Simula `ensureForGoogle` real: el usuario ya existe con un nombre
    // editado por él mismo, así que el `displayName` de Gmail se ignora y
    // el doc de Firestore vuelve tal cual estaba.
    return usuarioExistente;
  }

  @override
  Future<void> syncAuthDisplayName(String nombreCompleto) async {
    nombreSincronizadoEnAuth = nombreCompleto;
  }

  @override
  Future<ClientUserEntity?> getClientUserById(String uid) =>
      throw UnimplementedError();

  @override
  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  }) => throw UnimplementedError();

  @override
  Future<void> completeClientProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
    String? email,
  }) => throw UnimplementedError();

  @override
  Future<String> loginWithEmail({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<String> resolveUserRole(String uid) => throw UnimplementedError();

  @override
  Future<bool> isRegisteredAdmin(String uid) => throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();
}

void main() {
  test(
    'usuario ya registrado con nombre editado: el usecase enruta a clientHome '
    'y sincroniza Auth con el nombre GUARDADO, no con el de Gmail',
    () async {
      final usuarioExistente = ClientUserEntity(
        id: 'u1',
        nombre: 'Juan',
        apellido: 'Editado',
        telefono: '3001234567',
        fotoUrl: 'https://ejemplo.com/foto.webp',
        rol: 'cliente',
        isProfileComplete: true,
        createdAt: DateTime(2026, 1, 1),
        email: 'gmail-default@example.com',
      );
      final repo = _FakeClientAuthRepository(usuarioExistente: usuarioExistente);
      final usecase = SignInGoogleClientUseCase(repo);

      final result = await usecase();

      expect(result.destination, AuthFlowDestination.clientHome);
      expect(repo.nombreSincronizadoEnAuth, 'Juan Editado');
      expect(repo.nombreSincronizadoEnAuth, isNot(contains('Gmail')));
    },
  );
}
