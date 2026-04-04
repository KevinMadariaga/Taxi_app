import 'dart:io';

import 'package:taxi_app/core/auth/simple_auth_repository.dart';
import 'package:taxi_app/data/repositories/client_auth/client_auth_repository_impl.dart';
import 'package:taxi_app/domain/entities/auth_identity_entity.dart';
import 'package:taxi_app/domain/entities/client_user_entity.dart';
import 'package:taxi_app/domain/models/phone_verification_result.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
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
  Future<PhoneVerificationResult> sendPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) {
    return _clientRepo.sendPhoneOtp(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
    );
  }

  @override
  Future<AuthIdentityEntity> verifyPhoneOtp({
    required String verificationId,
    required String otpCode,
  }) {
    return _clientRepo.verifyPhoneOtp(
      verificationId: verificationId,
      otpCode: otpCode,
    );
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
  }) {
    return _clientRepo.ensureClientUserForGoogle(
      uid: uid,
      displayName: displayName,
      email: email,
    );
  }

  @override
  Future<ClientUserEntity> ensureClientUserForPhone({
    required String uid,
    required String phoneNumber,
  }) {
    return _clientRepo.ensureClientUserForPhone(
      uid: uid,
      phoneNumber: phoneNumber,
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
  }) {
    return _clientRepo.completeClientProfile(
      uid: uid,
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      fotoUrl: fotoUrl,
    );
  }
}
