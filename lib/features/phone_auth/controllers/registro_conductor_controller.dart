import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';

import '../services/storage_service.dart';
import '../services/user_data_service.dart';

class RegistroConductorController extends ChangeNotifier {
  RegistroConductorController({
    required this.adminId,
    StorageService? storageService,
    UserDataService? userDataService,
    ImageCropperService? imageCropperService,
    ImagePicker? imagePicker,
  }) : _storageService = storageService ?? StorageService(),
       _userDataService = userDataService ?? UserDataService(),
       _imageCropperService =
           imageCropperService ?? const ImageCropperService(),
       _imagePicker = imagePicker ?? ImagePicker();

  final String adminId;
  final StorageService _storageService;
  final UserDataService _userDataService;
  final ImageCropperService _imageCropperService;
  final ImagePicker _imagePicker;

  XFile? _fotoConductor;
  XFile? _fotoVehiculo;
  bool _saving = false;
  String? _generatedEmail;
  String? _generatedPassword;
  String _tipoVehiculo = 'carro';

  XFile? get fotoConductor => _fotoConductor;
  XFile? get fotoVehiculo => _fotoVehiculo;
  bool get saving => _saving;
  String? get generatedEmail => _generatedEmail;
  String? get generatedPassword => _generatedPassword;
  String get tipoVehiculo => _tipoVehiculo;

  void setTipoVehiculo(String tipo) {
    if (_tipoVehiculo == tipo) return;
    _tipoVehiculo = tipo;
    notifyListeners();
  }

  Future<void> pickFotoConductor() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 78,
      maxWidth: 1400,
    );
    if (picked == null) return;

    final cropped = await _imageCropperService.cropProfileImage(
      sourcePath: picked.path,
    );
    if (cropped == null) return;

    _fotoConductor = XFile(cropped.path);
    notifyListeners();
  }

  Future<void> pickFotoVehiculo() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (picked == null) return;

    final cropped = await _imageCropperService.cropVehicleImage(
      sourcePath: picked.path,
    );
    if (cropped == null) return;

    _fotoVehiculo = XFile(cropped.path);
    notifyListeners();
  }

  Future<String?> registrarConductor({
    required String nombre,
    required String telefono,
    required String placa,
  }) async {
    if (nombre.trim().isEmpty) {
      return 'Ingresa el nombre del conductor.';
    }
    final phoneDigits = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (phoneDigits.length < 7) {
      return 'Ingresa un numero telefonico valido.';
    }
    if (placa.trim().length < 5) {
      return 'Ingresa una placa valida.';
    }
    if (_fotoConductor == null) {
      return 'Selecciona la foto del conductor.';
    }
    if (_fotoVehiculo == null) {
      return 'Selecciona la foto del vehiculo.';
    }

    _saving = true;
    notifyListeners();

    try {
      final nombreGremio = await _userDataService
          .obtenerNombreGremioAdministrador(adminId: adminId);
      final credentials = await _userDataService.generarCredencialesConductor(
        nombre: nombre,
        nombreGremio: nombreGremio,
      );
      final idConductor = await _userDataService.crearConductorAuth(
        email: credentials.email,
        password: credentials.password,
      );

      final fotoConductorUrl = await _storageService.uploadImage(
        file: File(_fotoConductor!.path),
        path: 'conductores/$idConductor/foto_conductor.webp',
      );

      final fotoVehiculoUrl = await _storageService.uploadImage(
        file: File(_fotoVehiculo!.path),
        path: 'conductores/$idConductor/foto_vehiculo.webp',
      );

      await _userDataService.guardarConductor(
        idConductor: idConductor,
        nombre: nombre,
        telefono: phoneDigits,
        placa: placa,
        fotoConductor: fotoConductorUrl,
        fotoVehiculo: fotoVehiculoUrl,
        adminId: adminId,
        tipoVehiculo: _tipoVehiculo,
        correo: credentials.email,
        passwordLogin: credentials.password,
      );

      _generatedEmail = credentials.email;
      _generatedPassword = credentials.password;

      return null;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      if (msg.isNotEmpty) return msg;
      return 'No se pudo registrar el conductor.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
