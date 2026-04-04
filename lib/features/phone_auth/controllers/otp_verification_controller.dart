import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taxi_app/data/repositories/client_auth/client_auth_repository_impl.dart';
import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
import 'package:taxi_app/domain/usecases/client_auth/verify_client_phone_otp_usecase.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/phone_code_result_model.dart';
import '../services/user_data_service.dart';

class OtpVerificationController extends ChangeNotifier {
  OtpVerificationController({
    required String verificationId,
    required int? resendToken,
    required this.phoneNumber,
    required this.isAdminMode,
    ClientAuthRepository? clientAuthRepository,
    UserDataService? userDataService,
    VerifyClientPhoneOtpUseCase? verifyClientPhoneOtpUseCase,
    AuthService? authService,
  }) : _verificationId = verificationId,
       _resendToken = resendToken,
       _clientAuthRepository =
           clientAuthRepository ?? ClientAuthRepositoryImpl(),
       _userDataService = userDataService ?? UserDataService(),
       _verifyClientPhoneOtpUseCase =
           verifyClientPhoneOtpUseCase ??
           VerifyClientPhoneOtpUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           ),
       _authService = authService ?? AuthService();

  final ClientAuthRepository _clientAuthRepository;
  final UserDataService _userDataService;
  final VerifyClientPhoneOtpUseCase _verifyClientPhoneOtpUseCase;
  final AuthService _authService;

  final String phoneNumber;
  final bool isAdminMode;

  String _verificationId;
  int? _resendToken;

  String _otpCode = '';
  int _resendCountdown = 30;
  bool _loading = false;
  Timer? _timer;
  int _failedAttempts = 0;
  DateTime? _lockUntil;

  static const int _maxFailedAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 5);

  String get otpCode => _otpCode;
  int get resendCountdown => _resendCountdown;
  bool get canResend => _resendCountdown == 0 && !_loading;
  bool get loading => _loading;

  void startTimer() {
    _timer?.cancel();
    _resendCountdown = 30;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown == 0) {
        timer.cancel();
        return;
      }
      _resendCountdown -= 1;
      notifyListeners();
    });
  }

  void setCode(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (_otpCode == sanitized) return;
    _otpCode = sanitized;
    notifyListeners();
  }

  Future<AuthResolutionModel> verifyCode() async {
    if (_otpCode.length < 6) {
      throw StateError('Ingresa un codigo valido de 6 digitos.');
    }

    if (_lockUntil != null && DateTime.now().isBefore(_lockUntil!)) {
      final remaining = _lockUntil!.difference(DateTime.now()).inSeconds;
      throw StateError(
        'Has alcanzado el numero maximo de intentos. Intenta nuevamente en ${remaining}s.',
      );
    }

    _loading = true;
    notifyListeners();

    try {
      final normalizedPhone = _normalizeToTenDigits(phoneNumber);

      if (isAdminMode) {
        final identity = await _clientAuthRepository.verifyPhoneOtp(
          verificationId: _verificationId,
          otpCode: _otpCode,
        );

        final uid = identity.uid;
        if (uid.isEmpty) {
          throw StateError('No fue posible autenticar al usuario.');
        }

        await _authService.saveUserSession(
          role: 'administrador',
          isLoggedIn: true,
        );

        final adminExists = await _userDataService.administradorExiste(uid);
        return AuthResolutionModel(
          destination: adminExists
              ? AuthNextDestination.adminPanel
              : AuthNextDestination.adminRegistration,
          uid: uid,
          phoneNumber: normalizedPhone,
        );
      }

      final flow = await _verifyClientPhoneOtpUseCase(
        VerifyClientPhoneOtpParams(
          verificationId: _verificationId,
          otpCode: _otpCode,
          phoneNumber: phoneNumber,
        ),
      );

      await _authService.saveUserSession(role: 'cliente', isLoggedIn: true);

      return AuthResolutionModel(
        destination: flow.destination == AuthFlowDestination.clientHome
            ? AuthNextDestination.clientHome
            : AuthNextDestination.completeClientProfile,
        uid: flow.user.id,
        phoneNumber: _normalizeToTenDigits(
          flow.user.telefono.isNotEmpty ? flow.user.telefono : normalizedPhone,
        ),
      );
    } catch (e) {
      _failedAttempts += 1;
      if (_failedAttempts >= _maxFailedAttempts) {
        _lockUntil = DateTime.now().add(_lockDuration);
      }
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _normalizeToTenDigits(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }

  Future<void> resendCode() async {
    if (!canResend) return;

    _loading = true;
    notifyListeners();

    try {
      final result = await _clientAuthRepository.sendPhoneOtp(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
      );
      // convert domain model to local PhoneCodeResultModel
      _verificationId = result.verificationId;
      _resendToken = result.resendToken;
      startTimer();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
