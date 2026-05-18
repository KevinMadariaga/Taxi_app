import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
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

  Future<String> _uploadProfilePhoto(String uid, XFile file) async {
    final originalBytes = await file.readAsBytes();

    const int maxBytes = 100 * 1024;

    Uint8List compressed = Uint8List.fromList(originalBytes);

    final attempts = <Map<String, int>>[
      {'q': 80, 'w': 0},
      {'q': 70, 'w': 0},
      {'q': 60, 'w': 1280},
      {'q': 50, 'w': 1080},
      {'q': 45, 'w': 900},
      {'q': 40, 'w': 720},
      {'q': 35, 'w': 640},
      {'q': 30, 'w': 560},
      {'q': 25, 'w': 480},
    ];

    for (final a in attempts) {
      try {
        final q = a['q'] ?? 70;
        final w = a['w'] ?? 0;
        final result = w > 0
            ? await FlutterImageCompress.compressWithList(
                originalBytes,
                quality: q,
                rotate: 0,
                format: CompressFormat.webp,
                minWidth: w,
                minHeight: w,
              )
            : await FlutterImageCompress.compressWithList(
                originalBytes,
                quality: q,
                rotate: 0,
                format: CompressFormat.webp,
              );
        if (result.isEmpty) continue;
        final current = Uint8List.fromList(result);
        if (compressed.isEmpty || current.length < compressed.length) {
          compressed = current;
        }
        if (current.length <= maxBytes) {
          compressed = current;
          break;
        }
      } catch (_) {}
    }

    final ref = FirebaseStorage.instance
        .ref()
        .child('conductor_photos')
        .child('$uid.webp');
    final uploadTask = ref.putData(
      compressed,
      SettableMetadata(contentType: 'image/webp'),
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
