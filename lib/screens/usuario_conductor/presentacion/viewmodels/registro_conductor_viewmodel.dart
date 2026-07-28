import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/services/image_processing_service.dart';
import 'package:taxi_app/core/services/image_upload_service.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/model/registro_conductor_model.dart';

class RegistroConductorViewModel {
  final TextEditingController nombreController = TextEditingController();
  final TextEditingController telefonoController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController placaController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ImageProcessingService _imageProcessingService =
      const ImageProcessingService();
  final ImageUploadService _imageUploadService = ImageUploadService();

  final ValueNotifier<bool> isLoading = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<RegistroConductorModel?> conductor = ValueNotifier(null);
  final ValueNotifier<XFile?> selectedImage = ValueNotifier<XFile?>(null);

  RegistroConductorViewModel({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  Future<bool> register() async {
    if (!(formKey.currentState?.validate() ?? false)) return false;
    if (passwordController.text.trim() !=
        confirmPasswordController.text.trim()) {
      error.value = 'Las contraseñas no coinciden';
      return false;
    }

    isLoading.value = true;
    error.value = null;

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = credential.user?.uid;
      if (uid == null) {
        error.value = 'No se pudo obtener el uid del usuario';
        return false;
      }

      String? photoUrl;

      // Si hay imagen seleccionada, subirla primero y obtener URL
      if (selectedImage.value != null) {
        try {
          photoUrl = await _uploadProfilePhoto(uid, selectedImage.value!);
        } catch (e) {
          debugPrint('Error uploading profile photo: $e');
        }
      }

      final model = RegistroConductorModel(
        id: uid,
        correo: emailController.text.trim(),
        nombre: nombreController.text.trim(),
        telefono: telefonoController.text.trim(),
        placa: placaController.text.trim().toUpperCase(),
      );

      final docData = {
        'tipoUsuario': 'conductor',
        'conductorId': uid,
        ...model.toMap(),
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        docData['foto'] = photoUrl;
      }

      await _firestore.collection('usuarios').doc(uid).set({
        ...docData,
        'rol': 'conductor',
        'tipoUsuario': 'conductor',
      });

      // Guardar estado de sesión y rol
      await SessionHelper.saveSession('conductor', uid);

      conductor.value = model;
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        error.value = 'Este correo ya está registrado. Intenta con otro.';
      } else {
        error.value = e.message ?? e.code;
      }
      return false;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null) {
        selectedImage.value = picked;
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  /// Comprime y sube la foto de perfil vía los servicios compartidos
  /// ([ImageProcessingService]/[ImageUploadService]) en vez de reimplementar
  /// aquí su propia cadena de intentos de compresión.
  Future<String> _uploadProfilePhoto(String uid, XFile file) async {
    final compressed = await _imageProcessingService.compressProfilePhoto(
      File(file.path),
    );
    return _imageUploadService.uploadFile(
      file: compressed,
      storagePath: 'conductor_photos/$uid.webp',
    );
  }

  void dispose() {
    nombreController.dispose();
    telefonoController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    placaController.dispose();
    isLoading.dispose();
    error.dispose();
    conductor.dispose();
    selectedImage.dispose();
  }
}
