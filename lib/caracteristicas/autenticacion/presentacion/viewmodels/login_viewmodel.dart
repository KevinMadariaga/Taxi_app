import 'package:flutter/foundation.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/country_model.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/phone_verification_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/send_phone_otp_usecase.dart';

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required SendPhoneOtpUseCase sendPhoneOtpUseCase})
    : _sendPhoneOtpUseCase = sendPhoneOtpUseCase;

  final SendPhoneOtpUseCase _sendPhoneOtpUseCase;

  final List<CountryModel> countries = const [
    CountryModel(
      isoCode: 'CO',
      name: 'Colombia',
      dialCode: '+57',
      flagEmoji: '🇨🇴',
    ),
    CountryModel(
      isoCode: 'MX',
      name: 'Mexico',
      dialCode: '+52',
      flagEmoji: '🇲🇽',
    ),
    CountryModel(
      isoCode: 'US',
      name: 'Estados Unidos',
      dialCode: '+1',
      flagEmoji: '🇺🇸',
    ),
    CountryModel(
      isoCode: 'ES',
      name: 'Espana',
      dialCode: '+34',
      flagEmoji: '🇪🇸',
    ),
    CountryModel(
      isoCode: 'PE',
      name: 'Peru',
      dialCode: '+51',
      flagEmoji: '🇵🇪',
    ),
  ];

  late CountryModel _selectedCountry = countries.first;
  int _currentPage = 0;
  String _phoneNumber = '';
  String? _errorMessage;
  bool _isLoading = false;
  PhoneVerificationResult? _pendingOtpResult;

  CountryModel get selectedCountry => _selectedCountry;
  int get currentPage => _currentPage;
  String get phoneNumber => _phoneNumber;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  PhoneVerificationResult? get pendingOtpResult => _pendingOtpResult;

  String get fullPhoneNumber {
    final digits = _digitsOnly(_phoneNumber);
    return '${_selectedCountry.dialCode}$digits';
  }

  void onPageChanged(int page) {
    if (_currentPage == page) return;
    _currentPage = page;
    notifyListeners();
  }

  void updatePhoneNumber(String value) {
    _phoneNumber = value;
    if (_errorMessage != null) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void selectCountry(CountryModel? country) {
    if (country == null || country.isoCode == _selectedCountry.isoCode) return;
    _selectedCountry = country;
    notifyListeners();
  }

  String? validatePhoneNumber() {
    final digits = _digitsOnly(_phoneNumber);

    if (digits.isEmpty) {
      return 'Ingresa tu numero de telefono.';
    }

    if (digits.length < 7 || digits.length > 12) {
      return 'El numero debe tener entre 7 y 12 digitos.';
    }

    return null;
  }

  Future<void> sendVerificationCode() async {
    final validationError = validatePhoneNumber();
    if (validationError != null) {
      _errorMessage = validationError;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _sendPhoneOtpUseCase(
        SendPhoneOtpParams(phoneNumber: fullPhoneNumber),
      );

      _pendingOtpResult = result;
    } catch (error) {
      _errorMessage = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void consumeOtpNavigation() {
    _pendingOtpResult = null;
  }

  String _digitsOnly(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }
}
