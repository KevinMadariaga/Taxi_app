import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

/// Cobertura del guard de foto obligatoria: ni Google ni Apple entregan foto
/// en el sign-in (ambos usecases pasan `photoUrl: null` a propósito), así
/// que `usuarios/{uid}.foto` nace vacío en un alta nueva. Sin este guard,
/// `completeClientProfile` podía marcar `isProfileComplete: true` con la
/// foto en blanco.
class _FakeClientAuthRepository implements ClientAuthRepository {
  _FakeClientAuthRepository({ClientUserEntity? existing}) : _existing = existing;

  ClientUserEntity? _existing;
  bool completeClientProfileLlamado = false;

  @override
  Future<ClientUserEntity?> getClientUserById(String uid) async => _existing;

  @override
  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  }) async => 'https://ejemplo.com/nueva-foto.webp';

  @override
  Future<void> completeClientProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
    String? email,
  }) async {
    completeClientProfileLlamado = true;
    _existing = ClientUserEntity(
      id: uid,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      fotoUrl: fotoUrl ?? '',
      rol: 'cliente',
      isProfileComplete: true,
      createdAt: DateTime(2026, 1, 1),
      email: email,
    );
  }

  // Resto de la interfaz: sin uso en este test.
  @override
  Future<AuthIdentityEntity?> signInWithGoogle() async => null;

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
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
  group('CompleteClientProfileUseCase — guard de foto obligatoria', () {
    test(
      'sin foto nueva y sin foto previa: lanza y NO llama completeClientProfile '
      '(caso Apple/Google real: ambos entregan photoUrl null en el sign-in)',
      () async {
        final repo = _FakeClientAuthRepository(existing: null);
        final usecase = CompleteClientProfileUseCase(repo);

        await expectLater(
          usecase(
            const CompleteClientProfileParams(
              uid: 'u1',
              nombre: 'Ana',
              apellido: 'Pérez',
              telefono: '3001234567',
            ),
          ),
          throwsA(isA<StateError>()),
        );
        expect(repo.completeClientProfileLlamado, isFalse);
      },
    );

    test('con foto nueva (File): completa el perfil sin problema', () async {
      final repo = _FakeClientAuthRepository(existing: null);
      final usecase = CompleteClientProfileUseCase(repo);

      final resultado = await usecase(
        CompleteClientProfileParams(
          uid: 'u1',
          nombre: 'Ana',
          apellido: 'Pérez',
          telefono: '3001234567',
          profileImageFile: File('foto_local.jpg'),
        ),
      );

      expect(repo.completeClientProfileLlamado, isTrue);
      expect(resultado.fotoUrl, isNotEmpty);
    });

    test(
      'sin foto nueva pero CON foto previa guardada: completa el perfil '
      '(quien ya completó el perfil una vez no queda encerrado sin cámara)',
      () async {
        final repo = _FakeClientAuthRepository(
          existing: ClientUserEntity(
            id: 'u1',
            nombre: 'Ana',
            apellido: 'Pérez',
            telefono: '3001234567',
            fotoUrl: 'https://ejemplo.com/foto-previa.webp',
            rol: 'cliente',
            isProfileComplete: false,
            createdAt: DateTime(2025, 1, 1),
          ),
        );
        final usecase = CompleteClientProfileUseCase(repo);

        final resultado = await usecase(
          const CompleteClientProfileParams(
            uid: 'u1',
            nombre: 'Ana',
            apellido: 'Pérez',
            telefono: '3001234567',
          ),
        );

        expect(repo.completeClientProfileLlamado, isTrue);
        expect(resultado.fotoUrl, 'https://ejemplo.com/foto-previa.webp');
      },
    );
  });
}
