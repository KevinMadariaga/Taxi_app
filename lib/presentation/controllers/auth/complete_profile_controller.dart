import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/validators/name_validator.dart';
import 'package:taxi_app/core/validators/phone_validator.dart';
import 'package:taxi_app/domain/repositories/client_auth_repository.dart';
import 'package:taxi_app/data/repositories/client_auth/client_auth_repository_impl.dart';
import 'package:taxi_app/domain/entities/client_user_entity.dart';
import 'package:taxi_app/domain/usecases/client_auth/complete_client_profile_usecase.dart';
import 'package:taxi_app/domain/usecases/client_auth/get_client_user_usecase.dart';
import 'package:taxi_app/core/services/services.dart';

class CompleteProfileController extends ChangeNotifier {
  CompleteProfileController({
    required this.uid,
    GetClientUserUseCase? getClientUserUseCase,
    CompleteClientProfileUseCase? completeClientProfileUseCase,
    ClientAuthRepository? clientAuthRepository,
    ImagePicker? imagePicker,
    AuthService? authService,
  }) : _getClientUserUseCase =
         getClientUserUseCase ??
         GetClientUserUseCase(clientAuthRepository ?? ClientAuthRepositoryImpl()),
       _completeClientProfileUseCase =
         completeClientProfileUseCase ??
         CompleteClientProfileUseCase(clientAuthRepository ?? ClientAuthRepositoryImpl()),
       _imagePicker = imagePicker ?? ImagePicker(),
       _authService = authService ?? AuthService();

  final String uid;
  final GetClientUserUseCase _getClientUserUseCase;
  final CompleteClientProfileUseCase _completeClientProfileUseCase;
  final ImagePicker _imagePicker;
  final AuthService _authService;

  ClientUserEntity? _currentUser;
  XFile? _selectedImage;
  bool _loadingInitial = true;
  bool _saving = false;
  String? _errorMessage;

  ClientUserEntity? get currentUser => _currentUser;
  XFile? get selectedImage => _selectedImage;
  bool get loadingInitial => _loadingInitial;
  bool get saving => _saving;
  String? get errorMessage => _errorMessage;

  Future<void> loadInitialData() async {
    _loadingInitial = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _getClientUserUseCase(uid);
    } catch (_) {
      _errorMessage = 'No fue posible cargar la informacion inicial.';
    } finally {
      _loadingInitial = false;
      notifyListeners();
    }
  }

  Future<void> pickProfileImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      maxWidth: 512,
      maxHeight: 512,
    );

    if (picked == null) return;
    _selectedImage = picked;
    notifyListeners();
  }

  Future<String?> saveProfile({
    required String nombre,
    required String apellido,
    required String telefono,
    bool requireTelefono = true,
  }) async {
    final nombreError = NameValidator.validateRequired(
      nombre,
      fieldName: 'Nombre',
    );
    if (nombreError != null) return nombreError;

    final apellidoError = NameValidator.validateRequired(
      apellido,
      fieldName: 'Apellido',
    );
    if (apellidoError != null) return apellidoError;

    var telefonoNormalizado = _normalizeToTenDigits(telefono);
    if (telefonoNormalizado.isEmpty) {
      telefonoNormalizado = _normalizeToTenDigits(_currentUser?.telefono ?? '');
    }

    if (requireTelefono) {
      final telefonoError = PhoneValidator.validateTenDigits(
        telefonoNormalizado,
      );
      if (telefonoError != null) return telefonoError;
    } else if (telefonoNormalizado.isEmpty) {
      return 'No se pudo recuperar el telefono de verificacion.';
    }

    _saving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await _completeClientProfileUseCase(
        CompleteClientProfileParams(
          uid: uid,
          nombre: nombre.trim(),
          apellido: apellido.trim(),
          telefono: telefonoNormalizado,
          profileImageFile: _selectedImage != null
              ? File(_selectedImage!.path)
              : null,
        ),
      );

      _currentUser = updated;
      await _authService.saveUserSession(role: 'cliente', isLoggedIn: true);

      return null;
    } catch (error) {
      _errorMessage = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      return _errorMessage;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  String _normalizeToTenDigits(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return '';
    }
    if (digits.length <= 10) {
      return digits;
    }
    return digits.substring(digits.length - 10);
  }
}
