import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../services/storage_service.dart';
import '../services/user_data_service.dart';

class RegistroAdministradorController extends ChangeNotifier {
  RegistroAdministradorController({
    required this.uid,
    required this.telefono,
    StorageService? storageService,
    UserDataService? userDataService,
    ImageCropperService? imageCropperService,
    ImagePicker? imagePicker,
  }) : _storageService = storageService ?? StorageService(),
       _userDataService = userDataService ?? UserDataService(),
       _imageCropperService =
           imageCropperService ?? const ImageCropperService(),
       _imagePicker = imagePicker ?? ImagePicker();

  final String uid;
  final String telefono;
  final StorageService _storageService;
  final UserDataService _userDataService;
  final ImageCropperService _imageCropperService;
  final ImagePicker _imagePicker;

  XFile? _profileImage;
  bool _saving = false;

  XFile? get profileImage => _profileImage;
  bool get saving => _saving;

  Future<void> pickProfileImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1280,
    );
    if (picked == null) return;

    final cropped = await _imageCropperService.cropProfileImage(
      sourcePath: picked.path,
    );
    if (cropped == null) return;

    _profileImage = XFile(cropped.path);
    notifyListeners();
  }

  Future<String?> registerAdmin({
    required String nombre,
    required String gremio,
    String? telefonoParam,
  }) async {
    if (nombre.trim().isEmpty) {
      return 'Ingresa el nombre del administrador.';
    }
    if (gremio.trim().isEmpty) {
      return 'Ingresa el gremio o asociacion.';
    }
    final phoneCandidate = (telefonoParam ?? telefono).trim();
    if (phoneCandidate.isEmpty) {
      return 'Ingresa el teléfono.';
    }
    final phoneValid = RegExp(r'^\d{1,10}$');
    if (!phoneValid.hasMatch(phoneCandidate)) {
      return 'El teléfono debe contener hasta 10 dígitos y solo números.';
    }
    if (_profileImage == null) {
      return 'Selecciona una foto de perfil.';
    }

    _saving = true;
    notifyListeners();

    try {
      final profileUrl = await _storageService.uploadImage(
        file: File(_profileImage!.path),
        path:
            'administradores/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp',
      );

      final currentEmail = FirebaseAuth.instance.currentUser?.email;

      await _userDataService.guardarAdministrador(
        uid: uid,
        nombre: nombre,
        telefono: phoneCandidate,
        foto: profileUrl,
        gremio: gremio,
        correo: currentEmail,
      );
      return null;
    } catch (_) {
      return 'No se pudo registrar el administrador.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
