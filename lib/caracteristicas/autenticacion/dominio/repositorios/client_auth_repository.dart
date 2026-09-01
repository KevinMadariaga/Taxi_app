import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';

abstract class ClientAuthRepository {
  Future<AuthIdentityEntity?> signInWithGoogle();

  Future<ClientUserEntity?> getClientUserById(String uid);

  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
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

  /// Sincroniza el `displayName` de FirebaseAuth con el nombre guardado en
  /// Firestore, para que ningún lector que caiga en ese fallback (chat de
  /// soporte, perfil sin red) muestre el nombre viejo del proveedor
  /// (Google/Apple) tras un login o una edición de perfil. No-op si
  /// [nombreCompleto] viene vacío; nunca lanza (ver
  /// `ClientAuthFirebaseDataSource.updateDisplayName`).
  Future<void> syncAuthDisplayName(String nombreCompleto);

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
