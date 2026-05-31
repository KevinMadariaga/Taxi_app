import 'package:flutter/foundation.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/client_auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/send_client_phone_otp_usecase.dart';

import '../models/phone_code_result_model.dart';

class PhoneAuthController extends ChangeNotifier {
  PhoneAuthController({
    SendClientPhoneOtpUseCase? sendClientPhoneOtpUseCase,
    ClientAuthRepository? clientAuthRepository,
  }) : _sendClientPhoneOtpUseCase =
           sendClientPhoneOtpUseCase ??
           SendClientPhoneOtpUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           );

  final SendClientPhoneOtpUseCase _sendClientPhoneOtpUseCase;

  static const String adminSecret = '0210';

  final List<String> countryOptions = const ['+57'];

  String _countryCode = '+57';
  String _phone = '';
  bool _loading = false;
  bool _adminMode = false;

  String get countryCode => _countryCode;
  String get phone => _phone;
  bool get loading => _loading;
  bool get adminMode => _adminMode;

  String get fullPhone {
    final digits = _digitsOnly(_phone);
    return '$_countryCode$digits';
  }

  void setCountryCode(String value) {
    if (value != '+57') return;
    if (_countryCode == value) return;
    _countryCode = value;
    notifyListeners();
  }

  void setPhone(String value) {
    if (_phone == value) return;
    _phone = value;
    notifyListeners();
  }

  bool enableAdminMode(String secret) {
    if (secret.trim() != adminSecret) return false;
    _adminMode = true;
    notifyListeners();
    return true;
  }

  void disableAdminMode() {
    if (!_adminMode) return;
    _adminMode = false;
    notifyListeners();
  }

  String? validatePhone() {
    final digits = _digitsOnly(_phone);
    if (digits.isEmpty) {
      return 'Ingresa tu numero telefonico.';
    }
    if (_countryCode == '+57' && !RegExp(r'^3\d{9}$').hasMatch(digits)) {
      return 'Ingresa numero valido de 10 digitos.';
    }
    return null;
  }

  Future<PhoneCodeResultModel> sendCode() async {
    final error = validatePhone();
    if (error != null) {
      throw StateError(error);
    }

    _loading = true;
    notifyListeners();

    try {
      final result = await _sendClientPhoneOtpUseCase(
        SendClientPhoneOtpParams(phoneNumber: fullPhone),
      );
      return PhoneCodeResultModel(
        verificationId: result.verificationId,
        resendToken: result.resendToken,
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
