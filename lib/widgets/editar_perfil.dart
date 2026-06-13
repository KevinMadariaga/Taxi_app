import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:taxi_app/widgets/boton.dart';
import 'dart:ui' as ui;

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';

class EditarPerfilScreen extends StatefulWidget {
  final TextEditingController nombreController;
  final TextEditingController apellidoController;
  final TextEditingController telefonoController;
  final TextEditingController placaController;
  final bool esConductor;
  final File? selectedImage;
  final File? selectedVehicleImage;
  final Function(File?) onImageChanged;
  final Function(File?) onVehicleImageChanged;
  final Function(Map<String, dynamic>) onSave;

  const EditarPerfilScreen({
    Key? key,
    required this.nombreController,
    required this.apellidoController,
    required this.telefonoController,
    required this.placaController,
    required this.esConductor,
    this.selectedImage,
    this.selectedVehicleImage,
    required this.onImageChanged,
    required this.onVehicleImageChanged,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  bool get _hasChanges {
    final nombreChanged =
        widget.selectedImage != null &&
        widget.nombreController.text.trim() != widget.selectedImage?.path;
    final telefonoChanged =
        widget.selectedVehicleImage != null &&
        widget.telefonoController.text.trim() !=
            widget.selectedVehicleImage?.path;
    final placaChanged =
        widget.esConductor &&
        widget.placaController.text.trim() !=
            (widget.placaController.value.text.trim());
    final imageChanged = _image?.path != widget.selectedImage?.path;
    final vehicleChanged =
        widget.esConductor &&
        _vehicleImage?.path != widget.selectedVehicleImage?.path;
    return nombreChanged ||
        telefonoChanged ||
        placaChanged ||
        imageChanged ||
        vehicleChanged;
  }

  File? _image;
  File? _vehicleImage;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _imageCropperService = const ImageCropperService();

  @override
  void initState() {
    super.initState();
    _image = widget.selectedImage;
    _vehicleImage = widget.selectedVehicleImage;
  }

  Future<void> _pickImage(bool isVehicle) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) return;

      final cropped = isVehicle
          ? await _imageCropperService.cropVehicleImage(sourcePath: picked.path)
          : await _imageCropperService.cropProfileImage(
              sourcePath: picked.path,
            );
      if (cropped == null) return;

      final pickedFile = cropped;
      final compressed = await _compressFile(pickedFile, maxBytes: 100 * 1024);
      final fileSize = await compressed.length();
      if (fileSize > 100 * 1024) {
        AnimatedSnackBar.material(
          'La imagen seleccionada es mayor a 100KB. Selecciona una más pequeña.',
          type: AnimatedSnackBarType.warning,
        ).show(context);
        return;
      }
      setState(() {
        if (isVehicle) {
          _vehicleImage = compressed;
          widget.onVehicleImageChanged(compressed);
        } else {
          _image = compressed;
          widget.onImageChanged(compressed);
        }
      });
    } catch (e) {
      AnimatedSnackBar.material(
        'Error seleccionando imagen: $e',
        type: AnimatedSnackBarType.error,
      ).show(context);
    }
  }

  Future<File> _compressFile(File file, {required int maxBytes}) async {
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.webp';
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image original = frame.image;
      final int origW = original.width;
      final int origH = original.height;
      final qualities = [80, 70, 60, 50, 45, 40, 35, 30, 25];
      final scales = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4];
      File? best;
      for (final s in scales) {
        final targetW = (origW * s).toInt();
        final targetH = (origH * s).toInt();
        for (final q in qualities) {
          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            outPath,
            quality: q,
            minWidth: targetW,
            minHeight: targetH,
            format: CompressFormat.webp,
          );
          if (result == null) continue;
          final len = await result.length();
          final wrapped = File(result.path);
          best = wrapped;
          if (len <= maxBytes) return wrapped;
        }
      }
      return best ?? file;
    } catch (_) {
      return file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final avatarRadius = screenWidth * 0.20;
    final avatarIconSize = avatarRadius * 0.9;
    final cameraButtonRadius = avatarRadius * 0.28;
    final cameraIconSize = cameraButtonRadius * 0.9;
    final fieldFontSize = screenWidth * 0.045;
    final labelFontSize = screenWidth * 0.04;
    final vehicleImgWidth = screenWidth * 0.40;
    final vehicleImgHeight = screenHeight * 0.10;
    final vehicleCameraBtnSize = screenWidth * 0.09;
    final vehicleCameraIconSize = vehicleCameraBtnSize * 0.6;
    final buttonHeight = screenHeight * 0.055;
    final buttonFontSize = screenWidth * 0.045;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColores.primary,
        title: const Text(
          'Editar Perfil',
          style: TextStyle(color: AppColores.textWhite),
        ),
        iconTheme: const IconThemeData(color: AppColores.textWhite),
      ),
      backgroundColor: AppColores.background,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor: AppColores.grey200,
                        backgroundImage: _image != null
                            ? FileImage(_image!)
                            : null,
                        child: _image == null
                            ? Icon(
                                Icons.person,
                                size: avatarIconSize,
                                color: AppColores.textWhite,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: cameraButtonRadius * 0.5,
                        right: cameraButtonRadius * 0.5,
                        child: InkWell(
                          onTap: () => _pickImage(false),
                          child: CircleAvatar(
                            radius: cameraButtonRadius,
                            backgroundColor: AppColores.primary,
                            child: Icon(
                              Icons.camera_alt,
                              size: cameraIconSize,
                              color: AppColores.textWhite,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.03),
            TextField(
              controller: widget.nombreController,
              decoration: InputDecoration(
                labelText: 'Nombre',
                labelStyle: TextStyle(
                  fontSize: labelFontSize,
                  color: AppColores.textPrimary,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
              ),
              style: TextStyle(
                fontSize: fieldFontSize,
                color: AppColores.textPrimary,
              ),
            ),
            SizedBox(height: screenHeight * 0.02),
            TextField(
              controller: widget.apellidoController,
              decoration: InputDecoration(
                labelText: 'Apellido',
                labelStyle: TextStyle(
                  fontSize: labelFontSize,
                  color: AppColores.textPrimary,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
              ),
              style: TextStyle(
                fontSize: fieldFontSize,
                color: AppColores.textPrimary,
              ),
            ),
            SizedBox(height: screenHeight * 0.02),
            TextField(
              controller: widget.telefonoController,
              decoration: InputDecoration(
                labelText: 'Teléfono',
                labelStyle: TextStyle(
                  fontSize: labelFontSize,
                  color: AppColores.textPrimary,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColores.primary),
                ),
              ),
              keyboardType: TextInputType.phone,
              style: TextStyle(
                fontSize: fieldFontSize,
                color: AppColores.textPrimary,
              ),
            ),
            if (widget.esConductor) ...[
              SizedBox(height: screenHeight * 0.02),
              TextField(
                controller: widget.placaController,
                decoration: InputDecoration(
                  labelText: 'Placa',
                  labelStyle: TextStyle(
                    fontSize: labelFontSize,
                    color: AppColores.textPrimary,
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColores.primary),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColores.primary),
                  ),
                ),
                style: TextStyle(
                  fontSize: fieldFontSize,
                  color: AppColores.textPrimary,
                ),
              ),
              SizedBox(height: screenHeight * 0.02),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Foto del vehículo',
                      style: TextStyle(
                        fontSize: labelFontSize + 2,
                        fontWeight: FontWeight.w600,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Stack(
                      children: [
                        SizedBox(
                          width: vehicleImgWidth,
                          height: vehicleImgHeight,
                          child: _vehicleImage != null
                              ? Image.file(_vehicleImage!, fit: BoxFit.cover)
                              : Container(
                                  color: AppColores.grey200,
                                  child: Icon(
                                    Icons.directions_car,
                                    color: AppColores.textWhite,
                                    size: vehicleImgHeight * 0.5,
                                  ),
                                ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: () => _pickImage(true),
                            child: Container(
                              width: vehicleCameraBtnSize,
                              height: vehicleCameraBtnSize,
                              decoration: BoxDecoration(
                                color: AppColores.primary,
                                borderRadius: BorderRadius.circular(
                                  vehicleCameraBtnSize * 0.33,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: vehicleCameraIconSize,
                                color: AppColores.textWhite,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: screenHeight * 0.04),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Cancelar',
                    onPressed: () => Navigator.pop(context),
                    color: Colors.white,
                    textColor: AppColores.primary,
                    borderColor: AppColores.primary,
                    height: buttonHeight,
                    fontSize: buttonFontSize,
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                Expanded(
                  child: CustomButton(
                    text: 'Guardar',
                    onPressed: _isUploading
                        ? null
                        : () async {
                            if (!_hasChanges) {
                              Navigator.pop(context);
                              return;
                            }
                            setState(() => _isUploading = true);
                            try {
                              String? imageUrl;
                              String? vehicleUrl;
                              final uid = await _getUid();
                              // Siempre guardar en 'usuarios' (no en 'conductor' ni 'cliente')
                              // Subir imagen de perfil si hay nueva
                              if (_image != null && uid != null) {
                                final profileToUpload = await _compressFile(
                                  _image!,
                                  maxBytes: 100 * 1024,
                                );
                                final fileSize = await profileToUpload.length();
                                if (fileSize > 100 * 1024) {
                                  AnimatedSnackBar.material(
                                    'La imagen de perfil es mayor a 100KB. Selecciona una más pequeña.',
                                    type: AnimatedSnackBarType.warning,
                                  ).show(context);
                                  setState(() => _isUploading = false);
                                  return;
                                }
                                // Solo actualiza si es diferente
                                final prevDoc = await FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(uid)
                                    .get();
                                final prevUrl =
                                    prevDoc.data()?['foto'] as String?;
                                if (prevUrl == null ||
                                    prevUrl.isEmpty ||
                                    widget.selectedImage == null ||
                                    widget.selectedImage!.path != prevUrl) {
                                  // Eliminar imagen anterior si existe
                                  try {
                                    if (prevUrl != null && prevUrl.isNotEmpty) {
                                      await firebase_storage
                                          .FirebaseStorage
                                          .instance
                                          .refFromURL(prevUrl)
                                          .delete();
                                    }
                                  } catch (_) {}
                                  final path =
                                      'usuarios/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp';
                                  final ref = firebase_storage
                                      .FirebaseStorage
                                      .instance
                                      .ref()
                                      .child(path);
                                  final uploadTask = ref.putFile(
                                    profileToUpload,
                                  );
                                  final snapshot = await uploadTask;
                                  imageUrl = await snapshot.ref
                                      .getDownloadURL();
                                }
                              }
                              // Subir imagen de vehículo si hay nueva y es conductor
                              if (widget.esConductor &&
                                  _vehicleImage != null &&
                                  uid != null) {
                                final vehicleToUpload = await _compressFile(
                                  _vehicleImage!,
                                  maxBytes: 100 * 1024,
                                );
                                final fileSize = await vehicleToUpload.length();
                                if (fileSize > 100 * 1024) {
                                  AnimatedSnackBar.material(
                                    'La imagen del vehículo es mayor a 100KB. Selecciona una más pequeña.',
                                    type: AnimatedSnackBarType.warning,
                                  ).show(context);
                                  setState(() => _isUploading = false);
                                  return;
                                }
                                // Solo actualiza si es diferente
                                final prevDoc = await FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(uid)
                                    .get();
                                final prevUrl =
                                    prevDoc.data()?['fotoVehiculo'] as String?;
                                if (prevUrl == null ||
                                    prevUrl.isEmpty ||
                                    widget.selectedVehicleImage == null ||
                                    widget.selectedVehicleImage!.path !=
                                        prevUrl) {
                                  // Eliminar imagen anterior si existe
                                  try {
                                    if (prevUrl != null && prevUrl.isNotEmpty) {
                                      await firebase_storage
                                          .FirebaseStorage
                                          .instance
                                          .refFromURL(prevUrl)
                                          .delete();
                                    }
                                  } catch (_) {}
                                  final path =
                                      'usuarios/$uid/vehicle_${DateTime.now().millisecondsSinceEpoch}.webp';
                                  final ref = firebase_storage
                                      .FirebaseStorage
                                      .instance
                                      .ref()
                                      .child(path);
                                  final uploadTask = ref.putFile(
                                    vehicleToUpload,
                                  );
                                  final snapshot = await uploadTask;
                                  vehicleUrl = await snapshot.ref
                                      .getDownloadURL();
                                }
                              }
                              final Map<String, dynamic> datos = {};
                              datos['nombre'] = widget.nombreController.text
                                  .trim();
                              datos['apellido'] = widget.apellidoController.text
                                  .trim();
                              datos['telefono'] = widget.telefonoController.text
                                  .trim();
                              if (widget.esConductor) {
                                datos['placa'] = widget.placaController.text
                                    .trim();
                              }
                              if (imageUrl != null) {
                                datos['foto'] = imageUrl;
                              }
                              if (vehicleUrl != null) {
                                datos['fotoVehiculo'] = vehicleUrl;
                              }
                              widget.onSave(datos);
                              AnimatedSnackBar.material(
                                'Datos actualizados',
                                type: AnimatedSnackBarType.success,
                                duration: const Duration(seconds: 2),
                              ).show(context);
                              Navigator.pop(context);
                            } catch (e) {
                              AnimatedSnackBar.material(
                                'Error al guardar: $e',
                                type: AnimatedSnackBarType.error,
                              ).show(context);
                            } finally {
                              setState(() => _isUploading = false);
                            }
                          },
                    isLoading: _isUploading,
                    height: buttonHeight,
                    fontSize: buttonFontSize,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _getUid() async {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }
}
