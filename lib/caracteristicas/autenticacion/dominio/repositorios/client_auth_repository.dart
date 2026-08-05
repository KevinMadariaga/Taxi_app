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
    String? photoUrl,
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
    String? email,
  });

  /// Login legado con correo/contraseña (panel de administración/conductores).
  /// Devuelve el uid del usuario recién autenticado.
  Future<String> loginWithEmail({
    required String email,
    required String password,
  });

  /// Resuelve el rol (cliente/conductor/administrador) de [uid] desde
  /// `usuarios/{uid}`. `rol`/`role` son la fuente de verdad; `tipoUsuario`
  /// es solo un alias legacy de respaldo si esos dos no vinieron.
  /// Devuelve 'cliente' si no se pudo determinar.
  Future<String> resolveUserRole(String uid);

  /// Indica si [uid] tiene un documento propio en `administradores` (distinto
  /// de `usuarios.rol == 'admin'`, ambas señales se combinan al enrutar tras
  /// login social — ver `HomeView._navegarTrasLogin`).
  Future<bool> isRegisteredAdmin(String uid);

  Future<void> logout();
}
