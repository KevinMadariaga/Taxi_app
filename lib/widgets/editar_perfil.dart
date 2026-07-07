import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/widgets/boton.dart';
import 'package:taxi_app/widgets/flip_preview_view.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/services/image_processing_service.dart';
import 'package:taxi_app/core/services/face_detection_service.dart';

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
    final nombreChanged = widget.nombreController.text.trim() != _origNombre;
    final apellidoChanged =
        widget.apellidoController.text.trim() != _origApellido;
    final telefonoChanged =
        widget.telefonoController.text.trim() != _origTelefono;
    final placaChanged =
        widget.esConductor && widget.placaController.text.trim() != _origPlaca;
    final imageChanged = _imageChangedByUser;
    final vehicleChanged = widget.esConductor && _vehicleChangedByUser;
    return nombreChanged ||
        apellidoChanged ||
        telefonoChanged ||
        placaChanged ||
        imageChanged ||
        vehicleChanged;
  }

  File? _image;
  File? _vehicleImage;
  bool _imageChangedByUser = false;
  bool _vehicleChangedByUser = false;
  bool _isUploading = false;
  bool _isValidatingFace = false;
  late final String _origNombre;
  late final String _origApellido;
  late final String _origTelefono;
  late final String _origPlaca;
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _imageCropperService = const ImageCropperService();
  final ImageProcessingService _imageProcessingService =
      const ImageProcessingService();
  final FaceDetectionService _faceDetectionService = FaceDetectionService();

  @override
  void initState() {
    super.initState();
    _image = widget.selectedImage;
    _vehicleImage = widget.selectedVehicleImage;
    _origNombre = widget.nombreController.text.trim();
    _origApellido = widget.apellidoController.text.trim();
    _origTelefono = widget.telefonoController.text.trim();
    _origPlaca = widget.placaController.text.trim();
  }

  @override
  void dispose() {
    _faceDetectionService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isVehicle) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) return;

      File sourceFile = File(picked.path);

      // Foto de perfil: debe ser un rostro real, no cualquier objeto/escena.
      // Se valida ANTES del flip/crop para no hacerle perder tiempo al
      // usuario ajustando un recorte que de todas formas se va a rechazar.
      if (!isVehicle) {
        setState(() => _isValidatingFace = true);
        final tieneRostro = await _faceDetectionService.hasFace(
          sourceFile.path,
        );
        if (mounted) setState(() => _isValidatingFace = false);
        if (!tieneRostro) {
          if (!mounted) return;
          AnimatedSnackBar.material(
            'No se detectó un rostro claro en la foto. Asegúrate de mirar '
            'a la cámara con buena luz e inténtalo de nuevo.',
            type: AnimatedSnackBarType.warning,
          ).show(context);
          return;
        }

        if (!mounted) return;
        final flipped = await showFlipPreview(context, imageFile: sourceFile);
        if (flipped == null) return;
        sourceFile = flipped;
      }

      final cropped = isVehicle
          ? await _imageCropperService.cropVehicleImage(
              sourcePath: sourceFile.path,
            )
          : await _imageCropperService.cropProfileImage(
              sourcePath: sourceFile.path,
            );
      if (cropped == null) return;

      final compressed = isVehicle
          ? await _imageProcessingService.compressVehiclePhoto(cropped)
          : await _imageProcessingService.compressProfilePhoto(cropped);

      final maxBytes = isVehicle
          ? ImageProcessingService.vehicle16x9.maxBytes
          : ImageProcessingService.profile.maxBytes;
      final fileSize = await compressed.length();
      if (fileSize > maxBytes) {
        if (!mounted) return;
        AnimatedSnackBar.material(
          'No se pudo comprimir la imagen al peso permitido. Intenta con otra foto.',
          type: AnimatedSnackBarType.warning,
        ).show(context);
        return;
      }
      setState(() {
        if (isVehicle) {
          _vehicleImage = compressed;
          _vehicleChangedByUser = true;
        } else {
          _image = compressed;
          _imageChangedByUser = true;
        }
      });
    } catch (e) {
      AnimatedSnackBar.material(
        'Error seleccionando imagen: $e',
        type: AnimatedSnackBarType.error,
      ).show(context);
    }
  }

  Widget _sectionCard({
    required double screenWidth,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: AppColores.overlayLight,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String label,
    required double screenWidth,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(screenWidth * 0.018),
          decoration: BoxDecoration(
            color: AppColores.secondary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: screenWidth * 0.05, color: AppColores.secondary),
        ),
        SizedBox(width: screenWidth * 0.03),
        Text(
          label,
          style: TextStyle(
            fontSize: screenWidth * 0.042,
            fontWeight: FontWeight.w700,
            color: AppColores.textPrimary,
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColores.textSecondary),
      prefixIcon: Icon(icon, color: AppColores.secondary),
      filled: true,
      fillColor: AppColores.background,
      border: border(AppColores.divider, 1),
      enabledBorder: border(AppColores.divider, 1),
      focusedBorder: border(AppColores.secondary, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final avatarRadius = screenWidth * 0.18;
    final avatarIconSize = avatarRadius * 0.9;
    final cameraButtonRadius = avatarRadius * 0.28;
    final cameraIconSize = cameraButtonRadius * 0.9;
    final fieldFontSize = screenWidth * 0.042;
    final vehicleImgWidth = screenWidth * 0.42;
    final vehicleImgHeight = screenHeight * 0.11;
    final vehicleCameraBtnSize = screenWidth * 0.09;
    final vehicleCameraIconSize = vehicleCameraBtnSize * 0.6;
    final buttonHeight = screenHeight * 0.055;
    final buttonFontSize = screenWidth * 0.045;
    final fieldTextStyle = TextStyle(
      fontSize: fieldFontSize,
      color: AppColores.textPrimary,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColores.primary,
        elevation: 0,
        title: const Text(
          'Editar perfil',
          style: TextStyle(color: AppColores.textPrimary, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: AppColores.textPrimary),
      ),
      backgroundColor: AppColores.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            screenWidth * 0.04,
            screenWidth * 0.04,
            screenWidth * 0.04,
            screenWidth * 0.04 + screenHeight * 0.02,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColores.primary, width: 3),
                    ),
                    child: CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: AppColores.grey200,
                      backgroundImage: _image != null
                          ? FileImage(_image!)
                          : null,
                      child: _image == null
                          ? Icon(
                              Icons.person,
                              size: avatarIconSize,
                              color: AppColores.grey600,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: cameraButtonRadius * 0.4,
                    right: cameraButtonRadius * 0.4,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(cameraButtonRadius),
                      onTap: _isValidatingFace ? null : () => _pickImage(false),
                      child: CircleAvatar(
                        radius: cameraButtonRadius,
                        backgroundColor: AppColores.primary,
                        child: _isValidatingFace
                            ? SizedBox(
                                width: cameraIconSize,
                                height: cameraIconSize,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColores.textPrimary,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt,
                                size: cameraIconSize,
                                color: AppColores.textPrimary,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.03),
            _sectionCard(
              screenWidth: screenWidth,
              children: [
                _sectionHeader(
                  icon: Icons.badge_outlined,
                  label: 'Datos personales',
                  screenWidth: screenWidth,
                ),
                SizedBox(height: screenHeight * 0.02),
                TextField(
                  controller: widget.nombreController,
                  decoration: _fieldDecoration(
                    label: 'Nombre',
                    icon: Icons.person_outline,
                  ),
                  style: fieldTextStyle,
                ),
                SizedBox(height: screenHeight * 0.018),
                TextField(
                  controller: widget.apellidoController,
                  decoration: _fieldDecoration(
                    label: 'Apellido',
                    icon: Icons.person_outline,
                  ),
                  style: fieldTextStyle,
                ),
                SizedBox(height: screenHeight * 0.018),
                TextField(
                  controller: widget.telefonoController,
                  decoration: _fieldDecoration(
                    label: 'Teléfono',
                    icon: Icons.phone_outlined,
                  ),
                  keyboardType: TextInputType.phone,
                  style: fieldTextStyle,
                ),
              ],
            ),
            if (widget.esConductor) ...[
              SizedBox(height: screenHeight * 0.022),
              _sectionCard(
                screenWidth: screenWidth,
                children: [
                  _sectionHeader(
                    icon: Icons.directions_car_filled_outlined,
                    label: 'Vehículo',
                    screenWidth: screenWidth,
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  TextField(
                    controller: widget.placaController,
                    decoration: _fieldDecoration(
                      label: 'Placa',
                      icon: Icons.pin_outlined,
                    ),
                    style: fieldTextStyle,
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  Center(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: vehicleImgWidth,
                            height: vehicleImgHeight,
                            child: _vehicleImage != null
                                ? Image.file(_vehicleImage!, fit: BoxFit.cover)
                                : Container(
                                    color: AppColores.grey200,
                                    child: Icon(
                                      Icons.directions_car,
                                      color: AppColores.grey600,
                                      size: vehicleImgHeight * 0.5,
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              vehicleCameraBtnSize * 0.33,
                            ),
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
                                color: AppColores.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: screenHeight * 0.04),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Cancelar',
                    icon: const Icon(
                      Icons.close,
                      color: AppColores.secondary,
                      size: 18,
                    ),
                    onPressed: () => Navigator.pop(context),
                    color: Colors.white,
                    textColor: AppColores.secondary,
                    borderColor: AppColores.secondary,
                    height: buttonHeight,
                    fontSize: buttonFontSize,
                  ),
                ),
                SizedBox(width: screenWidth * 0.04),
                Expanded(
                  child: CustomButton(
                    text: 'Guardar',
                    icon: _isUploading
                        ? null
                        : const Icon(
                            Icons.check,
                            color: AppColores.textPrimary,
                            size: 18,
                          ),
                    textColor: AppColores.textPrimary,
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
                              // Subir imagen de perfil solo si el usuario tomó una nueva en esta sesión
                              if (_imageChangedByUser &&
                                  _image != null &&
                                  uid != null) {
                                // Ya se comprimió al tomar la foto (_pickImage);
                                // no recomprimir aquí para no gastar CPU de más.
                                final profileToUpload = _image!;
                                final prevDoc = await FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(uid)
                                    .get();
                                final prevUrl =
                                    prevDoc.data()?['foto'] as String?;
                                // Eliminar imagen anterior antes de subir la nueva
                                try {
                                  if (prevUrl != null && prevUrl.isNotEmpty) {
                                    await firebase_storage.FirebaseStorage
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
                                final uploadTask = ref.putFile(profileToUpload);
                                final snapshot = await uploadTask;
                                imageUrl = await snapshot.ref.getDownloadURL();
                                widget.onImageChanged(_image);
                              }
                              // Subir imagen de vehículo solo si el usuario tomó una nueva en esta sesión
                              if (widget.esConductor &&
                                  _vehicleChangedByUser &&
                                  _vehicleImage != null &&
                                  uid != null) {
                                // Ya se comprimió al tomar la foto (_pickImage);
                                // no recomprimir aquí para no gastar CPU de más.
                                final vehicleToUpload = _vehicleImage!;
                                final prevDoc = await FirebaseFirestore.instance
                                    .collection('usuarios')
                                    .doc(uid)
                                    .get();
                                final prevUrl =
                                    prevDoc.data()?['fotoVehiculo'] as String?;
                                // Eliminar imagen anterior antes de subir la nueva
                                try {
                                  if (prevUrl != null && prevUrl.isNotEmpty) {
                                    await firebase_storage.FirebaseStorage
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
                                final uploadTask = ref.putFile(vehicleToUpload);
                                final snapshot = await uploadTask;
                                vehicleUrl = await snapshot.ref.getDownloadURL();
                                widget.onVehicleImageChanged(_vehicleImage);
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
