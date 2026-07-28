import 'dart:io';

import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/client_auth_firebase_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/client_profile_image_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/client_user_firestore_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/simple_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/features/client/data/firebaseDB.dart';

class ClientAuthRepositoryImpl implements ClientAuthRepository {
  ClientAuthRepositoryImpl({
    ClientAuthFirebaseDataSource? authDataSource,
    ClientUserFirestoreDataSource? userDataSource,
    ClientProfileImageDataSource? imageDataSource,
    LegacyAuthRepository? legacyAuthRepository,
  }) : _authDataSource = authDataSource ?? ClientAuthFirebaseDataSource(),
       _userDataSource = userDataSource ?? ClientUserFirestoreDataSource(),
       _imageDataSource = imageDataSource ?? ClientProfileImageDataSource(),
       _legacyAuthRepository =
           legacyAuthRepository ?? LegacyAuthRepository(FirebaseDataSource());

  final ClientAuthFirebaseDataSource _authDataSource;
  final ClientUserFirestoreDataSource _userDataSource;
  final ClientProfileImageDataSource _imageDataSource;
  final LegacyAuthRepository _legacyAuthRepository;

  @override
  Future<AuthIdentityEntity?> signInWithGoogle() {
    return _authDataSource.signInWithGoogle();
  }

  @override
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) {
    return _authDataSource.sendPhoneOtp(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
    );
  }

  @override
  Future<AuthIdentityEntity> verifyPhoneOtp({
    required String verificationId,
    required String otpCode,
  }) {
    return _authDataSource.verifyPhoneOtp(
      verificationId: verificationId,
      otpCode: otpCode,
    );
  }

  @override
  Future<ClientUserEntity?> getClientUserById(String uid) {
    return _userDataSource.getById(uid);
  }

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
  }) {
    return _userDataSource.ensureForGoogle(
      uid: uid,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
    );
  }

  @override
  Future<ClientUserEntity> ensureClientUserForPhone({
    required String uid,
    required String phoneNumber,
  }) {
    return _userDataSource.ensureForPhone(uid: uid, phoneNumber: phoneNumber);
  }

  @override
  Future<String> uploadProfileImage({
    required String uid,
    required File imageFile,
  }) {
    return _imageDataSource.uploadProfileImage(uid: uid, file: imageFile);
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
    return _userDataSource.completeProfile(
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
    return _legacyAuthRepository.login(email, password);
  }

  @override
  Future<String> resolveUserRole(String uid) {
    return _userDataSource.resolveRole(uid);
  }

  @override
  Future<bool> isRegisteredAdmin(String uid) {
    return _userDataSource.isRegisteredAdmin(uid);
  }

  @override
  Future<void> logout() {
    return _legacyAuthRepository.logout();
  }
}
