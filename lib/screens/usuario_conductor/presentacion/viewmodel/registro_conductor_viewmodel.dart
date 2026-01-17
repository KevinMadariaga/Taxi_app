import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';
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
        placa: placaController.text.trim(),
      );

      final docData = {
        'tipoUsuario': 'conductor',
        'conductorId': uid,
        ...model.toMap(),
      };
      if (photoUrl != null && photoUrl.isNotEmpty) {
        docData['foto'] = photoUrl;
      }

      await _firestore.collection('conductor').doc(uid).set(docData);

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
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
      if (picked != null) {
        selectedImage.value = picked;
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<String> _uploadProfilePhoto(String uid, XFile file) async {
    final originalBytes = await file.readAsBytes();

    const int maxBytes = 300 * 1024; // 300 KB
    const int targetMinBytes = 150 * 1024; // 150 KB (attempt)

    List<int> compressed = originalBytes;

    // If already under max, start from original
    if (originalBytes.length > maxBytes) {
      // Try compressing reducing quality until under maxBytes or quality floor reached
      int quality = 85;
      while (quality >= 30) {
        try {
          final result = await FlutterImageCompress.compressWithList(
            originalBytes,
            quality: quality,
            rotate: 0,
          );
          if (result.isNotEmpty) compressed = result;
        } catch (_) {}

        if (compressed.length <= maxBytes) break;
        quality -= 5;
      }
    }

    // If compressed is now too small (< targetMinBytes) but original was larger,
    // try increasing quality to reach closer to targetMinBytes (best-effort).
    if (compressed.length < targetMinBytes && originalBytes.length > targetMinBytes) {
      for (int q in [95, 90, 88]) {
        try {
          final result = await FlutterImageCompress.compressWithList(
            originalBytes,
            quality: q,
            rotate: 0,
          );
          if (result.isNotEmpty) {
            compressed = result;
          }
        } catch (_) {}
        if (compressed.length >= targetMinBytes || compressed.length > maxBytes) break;
      }
    }

    // Final safety: if still larger than maxBytes, fall back to original resized
    if (compressed.length > maxBytes) {
      try {
        final result = await FlutterImageCompress.compressWithList(
          originalBytes,
          quality: 50,
          minWidth: 800,
          minHeight: 800,
        );
        if (result.isNotEmpty) compressed = result;
      } catch (_) {}
    }

    final ref = FirebaseStorage.instance.ref().child('conductor_photos').child('$uid.jpg');
    final uploadTask = ref.putData(
      Uint8List.fromList(compressed),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final snapshot = await uploadTask;
    final url = await snapshot.ref.getDownloadURL();
    return url;
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
