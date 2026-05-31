import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';

abstract class ClientAuthRepository {
  Future<AuthIdentityEntity?> signInWithGoogle();

  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  });

  Future<AuthIdentityEntity> verifyPhoneOtp({
    required String verificationId,
    required String otpCode,
  });

  Future<ClientUserEntity?> getClientUserById(String uid);

  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
  });

  Future<ClientUserEntity> ensureClientUserForPhone({
    required String uid,
    required String phoneNumber,
  });

  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  });

  Future<void> completeClientProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
  });
}
