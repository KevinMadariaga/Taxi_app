import 'package:flutter/foundation.dart';

import '../models/phone_code_result_model.dart';
import '../services/phone_auth_service.dart';

class PhoneAuthController extends ChangeNotifier {
  PhoneAuthController({PhoneAuthService? authService})
    : _authService = authService ?? PhoneAuthService();

  final PhoneAuthService _authService;

  static const String adminSecret = '0210';

  final List<String> countryOptions = const ['+57', '+52', '+1', '+34', '+51'];

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
    if (digits.length < 7 || digits.length > 12) {
      return 'El numero debe tener entre 7 y 12 digitos.';
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
      return await _authService.sendCode(phoneNumber: fullPhone);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
