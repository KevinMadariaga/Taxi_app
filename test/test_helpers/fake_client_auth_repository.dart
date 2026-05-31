import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

class FakeClientAuthRepository implements ClientAuthRepository {
  @override
  Future<AuthIdentityEntity?> signInWithGoogle() async {
    return const AuthIdentityEntity(
      uid: 'fake-uid',
      displayName: 'Fake',
      email: 'fake@example.com',
      phoneNumber: null,
    );
  }

  @override
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    return const PhoneVerificationResult(
      verificationId: 'fake-verification-id',
      resendToken: 1,
    );
  }

  @override
  Future<AuthIdentityEntity> verifyPhoneOtp({
    required String verificationId,
    required String otpCode,
  }) async {
    return const AuthIdentityEntity(
      uid: 'fake-uid',
      displayName: null,
      email: null,
      phoneNumber: '0000000000',
    );
  }

  @override
  Future<ClientUserEntity?> getClientUserById(String uid) async {
    return ClientUserEntity(
      id: uid,
      nombre: 'Nombre',
      apellido: 'Apellido',
      telefono: '0000000000',
      fotoUrl: '',
      rol: 'cliente',
      isProfileComplete: true,
      createdAt: DateTime.now(),
      email: 'fake@example.com',
    );
  }

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
  }) async {
    return (await getClientUserById(uid))!;
  }

  @override
  Future<ClientUserEntity> ensureClientUserForPhone({
    required String uid,
    required String phoneNumber,
  }) async {
    return ClientUserEntity(
      id: uid,
      nombre: 'Nombre',
      apellido: 'Apellido',
      telefono: phoneNumber,
      fotoUrl: '',
      rol: 'cliente',
      isProfileComplete: true,
      createdAt: DateTime.now(),
      email: null,
    );
  }

  @override
  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  }) async {
    return 'https://example.com/fake_profile.png';
  }

  @override
  Future<void> completeClientProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
  }) async {
    return;
  }
}
