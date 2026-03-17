import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/phone_code_result_model.dart';
import '../services/phone_auth_service.dart';
import '../services/user_data_service.dart';

class OtpVerificationController extends ChangeNotifier {
  OtpVerificationController({
    required String verificationId,
    required int? resendToken,
    required this.phoneNumber,
    required this.isAdminMode,
    PhoneAuthService? phoneAuthService,
    UserDataService? userDataService,
  }) : _verificationId = verificationId,
       _resendToken = resendToken,
       _phoneAuthService = phoneAuthService ?? PhoneAuthService(),
       _userDataService = userDataService ?? UserDataService();

  final PhoneAuthService _phoneAuthService;
  final UserDataService _userDataService;

  final String phoneNumber;
  final bool isAdminMode;

  String _verificationId;
  int? _resendToken;

  String _otpCode = '';
  int _resendCountdown = 30;
  bool _loading = false;
  Timer? _timer;

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

    _loading = true;
    notifyListeners();

    try {
      final credential = await _phoneAuthService.verifyCode(
        verificationId: _verificationId,
        otpCode: _otpCode,
      );

      final user = credential.user;
      if (user == null) {
        throw StateError('No fue posible autenticar al usuario.');
      }

      if (isAdminMode) {
        final adminExists = await _userDataService.administradorExiste(user.uid);
        return AuthResolutionModel(
          destination: adminExists
              ? AuthNextDestination.adminPanel
              : AuthNextDestination.adminRegistration,
          uid: user.uid,
          phoneNumber: phoneNumber,
        );
      }

      final userExists = await _userDataService.usuarioExiste(user.uid);
      return AuthResolutionModel(
        destination: userExists
            ? AuthNextDestination.clientHome
            : AuthNextDestination.clientRegistration,
        uid: user.uid,
        phoneNumber: phoneNumber,
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> resendCode() async {
    if (!canResend) return;

    _loading = true;
    notifyListeners();

    try {
      final result = await _phoneAuthService.sendCode(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
      );
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
