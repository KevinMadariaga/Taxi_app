import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';
import '../services/user_data_service.dart';

class RegistroAdministradorController extends ChangeNotifier {
  RegistroAdministradorController({
    required this.uid,
    required this.telefono,
    StorageService? storageService,
    UserDataService? userDataService,
    ImagePicker? imagePicker,
  }) : _storageService = storageService ?? StorageService(),
       _userDataService = userDataService ?? UserDataService(),
       _imagePicker = imagePicker ?? ImagePicker();

  final String uid;
  final String telefono;
  final StorageService _storageService;
  final UserDataService _userDataService;
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

    _profileImage = picked;
    notifyListeners();
  }

  Future<String?> registerAdmin({
    required String nombre,
    required String gremio,
  }) async {
    if (nombre.trim().isEmpty) {
      return 'Ingresa el nombre del administrador.';
    }
    if (gremio.trim().isEmpty) {
      return 'Ingresa el gremio o asociacion.';
    }
    if (_profileImage == null) {
      return 'Selecciona una foto de perfil.';
    }

    _saving = true;
    notifyListeners();

    try {
      final profileUrl = await _storageService.uploadImage(
        file: File(_profileImage!.path),
        path: 'administradores/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp',
      );

      await _userDataService.guardarAdministrador(
        uid: uid,
        nombre: nombre,
        telefono: telefono,
        foto: profileUrl,
        gremio: gremio,
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
