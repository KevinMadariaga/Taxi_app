import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/campos_modelo_color.dart';
import 'package:taxi_app/widgets/flip_preview_view.dart';
import 'package:taxi_app/widgets/elegir_origen_imagen_sheet.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/services/image_processing_service.dart';
import 'package:taxi_app/core/services/face_detection_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

class EditarPerfilScreen extends StatefulWidget {
  final TextEditingController nombreController;
  final TextEditingController apellidoController;
  final TextEditingController telefonoController;
  final TextEditingController placaController;

  /// Modelo y color del vehículo en uso (solo conductor).
  final TextEditingController? modeloController;
  final TextEditingController? colorController;

  /// 'carro' / 'moto': a qué entrada de `vehiculos` se copian los cambios.
  final String tipoVehiculo;
  final bool esConductor;
  final File? selectedImage;
  final File? selectedVehicleImage;
  final Future<void> Function(File?) onImageChanged;
  final Future<void> Function(File?) onVehicleImageChanged;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const EditarPerfilScreen({
    Key? key,
    required this.nombreController,
    required this.apellidoController,
    required this.telefonoController,
    required this.placaController,
    this.modeloController,
    this.colorController,
    this.tipoVehiculo = 'carro',
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
        widget.esConductor &&
        (widget.placaController.text.trim() != _origPlaca ||
            _modelo.text.trim() != _origModelo ||
            _color.text.trim() != _origColor);
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
  late final String _origModelo;
  late final String _origColor;

  // Si el llamador no los pasa, controllers propios (y se liberan aquí).
  late final TextEditingController _modelo =
      widget.modeloController ?? TextEditingController();
  late final TextEditingController _color =
      widget.colorController ?? TextEditingController();
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
    _origModelo = _modelo.text.trim();
    _origColor = _color.text.trim();
  }

  @override
  void dispose() {
    _faceDetectionService.dispose();
    if (widget.modeloController == null) _modelo.dispose();
    if (widget.colorController == null) _color.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isVehicle) async {
    try {
      if (!mounted) return;
      final origen = await mostrarElegirOrigenImagen(context);
      if (origen == null) return;

      final XFile? picked = await _picker.pickImage(
        source: origen,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (picked == null) return;

      File sourceFile = File(picked.path);

      // Foto de perfil: debe ser un rostro real, no cualquier objeto/escena.
      // Se valida ANTES del flip/crop para no hacerle perder tiempo al
      // usuario ajustando un recorte que de todas formas se va a rechazar.
      // Aplica sin importar el origen: sigue siendo la foto de perfil.
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

        // El "voltear" corrige el espejado que aplica la cámara frontal —
        // no aplica a una foto ya elegida de galería.
        if (origen == ImageSource.camera) {
          if (!mounted) return;
          final flipped = await showFlipPreview(context, imageFile: sourceFile);
          if (flipped == null) return;
          sourceFile = flipped;
        }
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
      if (!mounted) return;
      AnimatedSnackBar.material(
        'Error seleccionando imagen: $e',
        type: AnimatedSnackBarType.error,
      ).show(context);
    }
  }

  Future<void> _guardar() async {
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
      if (_imageChangedByUser && _image != null && uid != null) {
        // Ya se comprimió al tomar la foto (_pickImage);
        // no recomprimir aquí para no gastar CPU de más.
        final profileToUpload = _image!;
        final prevDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        final prevUrl = prevDoc.data()?['foto'] as String?;
        // Eliminar imagen anterior antes de subir la nueva
        try {
          if (prevUrl != null && prevUrl.isNotEmpty) {
            await firebase_storage.FirebaseStorage.instance
                .refFromURL(prevUrl)
                .delete();
          }
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'editar_perfil');
        }
        final path =
            'usuarios/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp';
        final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);
        // contentType explícito: `storage.rules`
        // exige `image/.*` en la escritura
        // (auditoría de seguridad), y esa condición
        // solo es fiable si el cliente lo manda.
        final uploadTask = ref.putFile(
          profileToUpload,
          firebase_storage.SettableMetadata(contentType: 'image/webp'),
        );
        final snapshot = await uploadTask;
        imageUrl = await snapshot.ref.getDownloadURL();
        await widget.onImageChanged(_image);
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
        final prevUrl = prevDoc.data()?['fotoVehiculo'] as String?;
        // Eliminar imagen anterior antes de subir la nueva
        try {
          if (prevUrl != null && prevUrl.isNotEmpty) {
            await firebase_storage.FirebaseStorage.instance
                .refFromURL(prevUrl)
                .delete();
          }
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'editar_perfil');
        }
        final path =
            'usuarios/$uid/vehicle_${DateTime.now().millisecondsSinceEpoch}.webp';
        final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);
        // contentType explícito: `storage.rules`
        // exige `image/.*` en la escritura
        // (auditoría de seguridad), y esa condición
        // solo es fiable si el cliente lo manda.
        final uploadTask = ref.putFile(
          vehicleToUpload,
          firebase_storage.SettableMetadata(contentType: 'image/webp'),
        );
        final snapshot = await uploadTask;
        vehicleUrl = await snapshot.ref.getDownloadURL();
        await widget.onVehicleImageChanged(_vehicleImage);
      }
      final Map<String, dynamic> datos = {};
      datos['nombre'] = widget.nombreController.text.trim();
      datos['apellido'] = widget.apellidoController.text.trim();
      datos['telefono'] = widget.telefonoController.text.trim();
      if (imageUrl != null) {
        datos['foto'] = imageUrl;
      }
      if (widget.esConductor) {
        final placa = widget.placaController.text.trim().toUpperCase();
        final modelo = _modelo.text.trim();
        final color = _color.text.trim();
        datos['placa'] = placa;
        datos['modeloVehiculo'] = modelo;
        datos['colorVehiculo'] = color;
        if (vehicleUrl != null) datos['fotoVehiculo'] = vehicleUrl;
        // Misma info en la entrada del vehículo en uso de `vehiculos`: es lo
        // que carga "Mis vehículos" (antes solo se tocaba la raíz y esa
        // pantalla seguía mostrando la placa vieja).
        datos['vehiculos'] = {
          widget.tipoVehiculo: {
            'placa': placa,
            'modelo': modelo,
            'color': color,
            'foto': ?vehicleUrl,
          },
        };
      }
      await widget.onSave(datos);
      if (!mounted) return;
      mostrarAvisoExito(
        context,
        titulo: 'Perfil actualizado',
        mensaje: 'Tus cambios quedaron guardados.',
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AnimatedSnackBar.material(
        'Error al guardar: $e',
        type: AnimatedSnackBarType.error,
      ).show(context);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.05 : 32.0;
    final avatar = esMovil ? 104.0 : 124.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Editar perfil'),
      bottomNavigationBar: BarraAccionInferior(
        texto: 'Guardar cambios',
        icono: Icons.check_rounded,
        cargando: _isUploading,
        onPressed: _isValidatingFace ? null : _guardar,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _isValidatingFace || _isUploading
                          ? null
                          : () => _pickImage(false),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColores.brand400, AppColores.brand500],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.background,
                          ),
                          child: ClipOval(
                            child: SizedBox.square(
                              dimension: avatar,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (_image != null)
                                    Image.file(
                                      _image!,
                                      fit: BoxFit.cover,
                                      cacheWidth: (avatar * dpr).round(),
                                      gaplessPlayback: true,
                                    )
                                  else
                                    ColoredBox(
                                      color: palette.grey200,
                                      child: Icon(
                                        Icons.person_rounded,
                                        size: avatar * 0.5,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  if (_isValidatingFace)
                                    const ColoredBox(
                                      color: Colors.black45,
                                      child: Center(
                                        child: SizedBox(
                                          width: 28,
                                          height: 28,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _isValidatingFace || _isUploading
                          ? null
                          : () => _pickImage(false),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(
                        _isValidatingFace
                            ? 'Verificando tu rostro…'
                            : 'Cambiar foto',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: acentoMarca(context),
                        iconColor: AppColores.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _grupo('Datos personales', [
                    _Campo(
                      etiqueta: 'Nombre',
                      controller: widget.nombreController,
                      icono: Icons.person_outline_rounded,
                      hint: 'Ej. Laura',
                      enabled: !_isUploading,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(40)],
                    ),
                    _Campo(
                      etiqueta: 'Apellido',
                      controller: widget.apellidoController,
                      icono: Icons.badge_outlined,
                      hint: 'Ej. Gómez',
                      enabled: !_isUploading,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [LengthLimitingTextInputFormatter(40)],
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _grupo('Contacto', [
                    _Campo(
                      etiqueta: 'Celular',
                      controller: widget.telefonoController,
                      icono: Icons.phone_iphone_rounded,
                      hint: '300 123 4567',
                      prefijo: '+57',
                      enabled: !_isUploading,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                  ]),
                  if (widget.esConductor) ...[
                    const SizedBox(height: 18),
                    _grupo('Vehículo', [
                      _Campo(
                        etiqueta: 'Placa',
                        controller: widget.placaController,
                        icono: Icons.pin_outlined,
                        hint: 'ABC123',
                        enabled: !_isUploading,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[A-Za-z0-9]'),
                          ),
                          LengthLimitingTextInputFormatter(7),
                          TextInputFormatter.withFunction(
                            (_, nuevo) =>
                                nuevo.copyWith(text: nuevo.text.toUpperCase()),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        child: CamposModeloColor(
                          modeloController: _modelo,
                          colorController: _color,
                          tipo: widget.tipoVehiculo == 'moto'
                              ? 'moto'
                              : 'carro',
                          enabled: !_isUploading,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                        child: _fotoVehiculo(palette),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Título de sección + tarjeta con los campos (sin separadores: cada
  /// campo ya trae su propio borde).
  Widget _grupo(String titulo, List<Widget> campos) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            titulo.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: palette.textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: campos,
          ),
        ),
      ],
    );
  }

  Widget _fotoVehiculo(AppPalette palette) {
    return Material(
      color: palette.grey100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.grey300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isUploading ? null : () => _pickImage(true),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_vehicleImage != null)
                Image.file(
                  _vehicleImage!,
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  gaplessPlayback: true,
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 30,
                      color: AppColores.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Toca para agregar la foto del vehículo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              if (_vehicleImage != null)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 15, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Cambiar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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

/// Campo con etiqueta arriba y borde que se resalta en naranja al enfocar
/// (visible también en modo oscuro).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.etiqueta,
    required this.controller,
    required this.icono,
    required this.hint,
    required this.enabled,
    this.prefijo,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final String etiqueta;
  final TextEditingController controller;
  final IconData icono;
  final String hint;
  final bool enabled;
  final String? prefijo;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    OutlineInputBorder borde(Color color, double ancho) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: ancho),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            cursorColor: AppColores.primary,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontWeight: FontWeight.w400,
                color: palette.textSecondary.withValues(alpha: 0.7),
              ),
              prefixIcon: Icon(icono, size: 21, color: palette.textSecondary),
              prefixText: prefijo == null ? null : '$prefijo  ',
              prefixStyle: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
              filled: true,
              fillColor: palette.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
              enabledBorder: borde(palette.grey300, 1.2),
              disabledBorder: borde(palette.grey200, 1.2),
              focusedBorder: borde(AppColores.primary, 1.8),
            ),
          ),
        ],
      ),
    );
  }
}
