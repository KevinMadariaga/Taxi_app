import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/services/image_processing_service.dart';
import 'package:taxi_app/core/services/image_upload_service.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/validators/vehiculo_validator.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/campos_modelo_color.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Gestión de DOS vehículos (carro y moto).
/// Cada tipo tiene su propia foto y placa almacenadas en
/// `usuarios/{uid}.vehiculos.{tipo}`.
/// - "Guardar datos": guarda foto/placa del tipo seleccionado sin cambiar el activo.
/// - "Usar {tipo}": guarda + activa ese tipo (actualiza root fields).
class CambiarVehiculoView extends StatefulWidget {
  const CambiarVehiculoView({super.key});

  @override
  State<CambiarVehiculoView> createState() => _CambiarVehiculoViewState();
}

class _CambiarVehiculoViewState extends State<CambiarVehiculoView> {
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _cropper = const ImageCropperService();
  final ImageProcessingService _imageProcessingService =
      const ImageProcessingService();
  late final ImageUploadService _imageUploadService = ImageUploadService();
  final UserDataService _userDataService = UserDataService();

  VehicleType _tipo = VehicleType.carro;
  VehicleType? _tipoActivo; // tipo activo guardado en Firestore

  final Map<VehicleType, TextEditingController> _placas = {
    VehicleType.carro: TextEditingController(),
    VehicleType.moto: TextEditingController(),
  };
  final Map<VehicleType, TextEditingController> _modelos = {
    VehicleType.carro: TextEditingController(),
    VehicleType.moto: TextEditingController(),
  };
  final Map<VehicleType, TextEditingController> _colores = {
    VehicleType.carro: TextEditingController(),
    VehicleType.moto: TextEditingController(),
  };
  final Map<VehicleType, XFile?> _fotosNuevas = {
    VehicleType.carro: null,
    VehicleType.moto: null,
  };
  final Map<VehicleType, String> _fotosUrl = {
    VehicleType.carro: '',
    VehicleType.moto: '',
  };

  bool _cargando = true;
  bool _guardando = false;
  bool _activando = false;
  // Confirmación visual breve tras guardar, sobre el cuadro de la foto del
  // tipo que se acaba de guardar (para validar que sí quedó en la BD).
  VehicleType? _tipoGuardadoOk;
  String? _errorFoto;
  String? _errorPlaca;
  String? _errorModelo;
  String? _errorColor;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final data = await _userDataService.getUsuario(uid);
      if (data != null && mounted) {
        final tipoStr = (data['tipoVehiculo'] ?? '').toString().toLowerCase();
        _tipoActivo = tipoStr == 'moto' ? VehicleType.moto : VehicleType.carro;
        _tipo = _tipoActivo!;

        final vehiculos = data['vehiculos'];
        final Map<String, dynamic> mapa = vehiculos is Map
            ? Map<String, dynamic>.from(vehiculos)
            : <String, dynamic>{};

        for (final t in VehicleType.values) {
          final v = mapa[t.firestoreKey];
          if (v is Map) {
            _fotosUrl[t] = (v['foto'] ?? '').toString();
            _placas[t]!.text = (v['placa'] ?? '').toString();
            _modelos[t]!.text = (v['modelo'] ?? '').toString();
            _colores[t]!.text = (v['color'] ?? '').toString();
          }
        }

        // Migración legacy: campos raíz → sub-doc del tipo activo.
        final activeKey = _tipoActivo!.firestoreKey;
        if (mapa[activeKey] is! Map) {
          final t = _tipoActivo!;
          final legacyFoto = (data['fotoVehiculo'] ?? '').toString();
          final legacyPlaca = (data['placa'] ?? '').toString();
          if (legacyFoto.isNotEmpty) _fotosUrl[t] = legacyFoto;
          if (legacyPlaca.isNotEmpty && _placas[t]!.text.isEmpty) {
            _placas[t]!.text = legacyPlaca;
          }
        }
        // Modelo/color del vehículo en uso también viven en la raíz (los
        // escribe el registro de conductor): completar si el mapa no los
        // tiene.
        final t = _tipoActivo!;
        if (_modelos[t]!.text.isEmpty) {
          _modelos[t]!.text = (data['modeloVehiculo'] ?? '').toString();
        }
        if (_colores[t]!.text.isEmpty) {
          _colores[t]!.text = (data['colorVehiculo'] ?? '').toString();
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'cambiar_vehiculo_view');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      ..._placas.values,
      ..._modelos.values,
      ..._colores.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final cropped = await _cropper.cropVehicleImage(sourcePath: picked.path);
      if (cropped == null) return;

      final compressed = await _imageProcessingService.compressVehiclePhoto(
        cropped,
      );
      final fileSize = await compressed.length();
      if (fileSize > ImageProcessingService.vehicle16x9.maxBytes) {
        if (!mounted) return;
        _mostrarError(
          'No se pudo comprimir la imagen al peso permitido. Intenta con otra foto.',
        );
        return;
      }

      setState(() {
        _fotosNuevas[_tipo] = XFile(compressed.path);
        _errorFoto = null;
      });
    } catch (e) {
      if (!mounted) return;
      _mostrarError('Error seleccionando imagen: $e');
    }
  }

  /// Sube la foto del tipo actual y borra la anterior de Storage (si había),
  /// para no acumular fotos huérfanas cada vez que el conductor cambia la
  /// foto de un mismo vehículo.
  Future<String> _subirImagen(XFile file, String uid) async {
    final previousUrl = _fotosUrl[_tipo];
    final path =
        'usuarios/$uid/fotoVehiculo_${_tipo.firestoreKey}_${DateTime.now().millisecondsSinceEpoch}.webp';
    final url = await _imageUploadService.uploadFile(
      file: File(file.path),
      storagePath: path,
    );

    if (previousUrl != null && previousUrl.isNotEmpty && previousUrl != url) {
      await _imageUploadService.deleteByUrl(previousUrl);
    }

    return url;
  }

  bool _tieneDataCompleta(VehicleType t) =>
      (_fotosUrl[t]!.isNotEmpty || _fotosNuevas[t] != null) &&
      _placas[t]!.text.trim().isNotEmpty &&
      _modelos[t]!.text.trim().isNotEmpty &&
      _colores[t]!.text.trim().isNotEmpty;

  /// Guarda foto + placa del tipo actual SIN cambiar el vehículo activo.
  Future<void> _guardarDatos() async {
    if (_guardando || _activando) return;
    if (!_validar()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotosNuevas[_tipo] != null
          ? await _subirImagen(_fotosNuevas[_tipo]!, uid)
          : _fotosUrl[_tipo]!;
      final placaUp = _placas[_tipo]!.text.trim().toUpperCase();

      await _userDataService.guardarVehiculo(
        uid: uid,
        tipo: _tipo.firestoreKey,
        foto: fotoUrl,
        placa: placaUp,
        modelo: _modelos[_tipo]!.text,
        color: _colores[_tipo]!.text,
      );

      // Confirma que el doc realmente quedó con estos datos antes de avisar
      // "guardado" — evita mostrar éxito si Firestore rechazó el merge.
      final verifyData = await _userDataService.getUsuario(uid);
      final verifyVehiculos = verifyData?['vehiculos'];
      final verifyEntry = verifyVehiculos is Map
          ? verifyVehiculos[_tipo.firestoreKey]
          : null;
      final guardadoOk =
          verifyEntry is Map &&
          (verifyEntry['foto'] ?? '').toString() == fotoUrl &&
          (verifyEntry['placa'] ?? '').toString() == placaUp;
      if (!guardadoOk) {
        throw StateError('La base de datos no reflejó los datos guardados.');
      }

      if (!mounted) return;
      final tipoGuardado = _tipo;
      setState(() {
        _fotosUrl[_tipo] = fotoUrl;
        _fotosNuevas[_tipo] = null;
        _placas[_tipo]!.text = placaUp;
        _tipoGuardadoOk = tipoGuardado;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted || _tipoGuardadoOk != tipoGuardado) return;
        setState(() => _tipoGuardadoOk = null);
      });
      mostrarAvisoExito(
        context,
        titulo: '${_tipo.label} guardado',
        mensaje: 'La foto y la placa quedaron registradas.',
      );
    } catch (e) {
      if (mounted) _mostrarError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Guarda foto + placa Y activa este vehículo como el activo.
  Future<void> _activarVehiculo() async {
    if (_guardando || _activando) return;
    if (!_validar()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida.');
      return;
    }

    setState(() => _activando = true);
    try {
      final fotoUrl = _fotosNuevas[_tipo] != null
          ? await _subirImagen(_fotosNuevas[_tipo]!, uid)
          : _fotosUrl[_tipo]!;
      final placaUp = _placas[_tipo]!.text.trim().toUpperCase();

      await _userDataService.activarVehiculo(
        uid: uid,
        tipo: _tipo.firestoreKey,
        foto: fotoUrl,
        placa: placaUp,
        modelo: _modelos[_tipo]!.text,
        color: _colores[_tipo]!.text,
      );

      // Confirma que el doc realmente quedó activo con estos datos antes de
      // avisar éxito y cerrar la pantalla.
      final verifyData = await _userDataService.getUsuario(uid);
      final activadoOk =
          (verifyData?['tipoVehiculo'] ?? '').toString() ==
              _tipo.firestoreKey &&
          (verifyData?['fotoVehiculo'] ?? '').toString() == fotoUrl;
      if (!activadoOk) {
        throw StateError('La base de datos no reflejó la activación.');
      }

      if (!mounted) return;
      setState(() {
        _tipoActivo = _tipo;
        _fotosUrl[_tipo] = fotoUrl;
        _fotosNuevas[_tipo] = null;
        _placas[_tipo]!.text = placaUp;
      });
      mostrarAvisoExito(
        context,
        titulo: 'Ahora conduces ${_tipo.label.toLowerCase()}',
        mensaje: 'Recibirás solicitudes para este vehículo.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _activando = false);
        _mostrarError('No se pudo activar: $e');
      }
    }
  }

  /// Marca bajo cada dato lo que falta (los dos a la vez), en vez de un
  /// snackbar que tapa los botones.
  bool _validar() {
    final label = _tipo.label.toLowerCase();
    final tieneFoto =
        _fotosNuevas[_tipo] != null || _fotosUrl[_tipo]!.isNotEmpty;
    final placa = _placas[_tipo]!.text.trim();
    setState(() {
      _errorFoto = tieneFoto ? null : 'Agrega la foto de tu $label.';
      _errorPlaca = placa.isEmpty
          ? 'Escribe la placa de tu $label.'
          : placa.length < 5
          ? 'La placa parece incompleta (ej. ABC123).'
          : null;
      _errorModelo = VehiculoValidator.modelo(
        _modelos[_tipo]!.text,
        tipo: label,
      );
      _errorColor = VehiculoValidator.color(_colores[_tipo]!.text, tipo: label);
    });
    if (_errorFoto != null ||
        _errorPlaca != null ||
        _errorModelo != null ||
        _errorColor != null) {
      HapticFeedback.mediumImpact();
      return false;
    }
    return true;
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColores.error),
    );
  }

  void _cambiarTipo(VehicleType tipo) {
    if (_tipo == tipo) return;
    setState(() {
      _tipo = tipo;
      _errorFoto = null;
      _errorPlaca = null;
      _errorModelo = null;
      _errorColor = null;
    });
  }

  Widget _tipoCard(VehicleType tipo, IconData icon) {
    final palette = context.palette;
    final sel = _tipo == tipo;
    final activo = _tipoActivo == tipo;
    final tieneData = _tieneDataCompleta(tipo);

    return Material(
      color: sel
          ? Color.alphaBlend(
              AppColores.primary.withValues(alpha: 0.14),
              palette.surface,
            )
          : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: sel ? AppColores.primary : palette.grey300,
          width: sel ? 2 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _guardando || _activando ? null : () => _cambiarTipo(tipo),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      icon,
                      size: 36,
                      color: sel ? acentoMarca(context) : palette.textSecondary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tipo.label,
                      style: TextStyle(
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (activo)
                      _Badge('En uso', acentoMarca(context))
                    else if (tieneData)
                      const _Badge('Registrado', AppColores.success)
                    else
                      _Badge('Sin datos', palette.textSecondary),
                  ],
                ),
              ),
            ),
            if (sel)
              const Positioned(
                top: 10,
                right: 10,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColores.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String texto, String ayuda) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          texto,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          ayuda,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _error(String? mensaje) => AnimatedSize(
    duration: const Duration(milliseconds: 200),
    child: mensaje == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppColores.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColores.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _foto() {
    final palette = context.palette;
    final fotoNueva = _fotosNuevas[_tipo];
    final fotoUrl = _fotosUrl[_tipo]!;
    final tieneFoto = fotoNueva != null || fotoUrl.isNotEmpty;

    final Widget contenido;
    if (fotoNueva != null) {
      contenido = Image.file(
        File(fotoNueva.path),
        fit: BoxFit.cover,
        cacheWidth: 900,
      );
    } else if (fotoUrl.isNotEmpty) {
      contenido = CachedNetworkImage(
        imageUrl: fotoUrl,
        fit: BoxFit.cover,
        memCacheWidth: 900,
        placeholder: (_, _) => const Center(
          child: CircularProgressIndicator(color: AppColores.primary),
        ),
        errorWidget: (_, _, _) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 40,
            color: palette.textSecondary,
          ),
        ),
      );
    } else {
      contenido = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColores.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_a_photo_outlined,
              color: acentoMarca(context),
              size: 26,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Toca para agregar la foto',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      );
    }

    Widget pastilla(IconData icono, String texto, Color fondo) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _errorFoto != null ? AppColores.error : palette.grey300,
          width: _errorFoto != null ? 1.8 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _guardando || _activando ? null : _pickImage,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              contenido,
              if (tieneFoto)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: pastilla(
                    Icons.edit_rounded,
                    'Cambiar',
                    Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              if (_tipoGuardadoOk == _tipo)
                Positioned(
                  top: 10,
                  left: 10,
                  child: pastilla(
                    Icons.check_circle_rounded,
                    'Guardado',
                    AppColores.success,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoPlaca() {
    final palette = context.palette;
    final conError = _errorPlaca != null;
    return TextField(
      controller: _placas[_tipo],
      enabled: !_guardando && !_activando,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(7),
        TextInputFormatter.withFunction(
          (_, nuevo) => nuevo.copyWith(text: nuevo.text.toUpperCase()),
        ),
      ],
      onChanged: (_) => setState(() => _errorPlaca = null),
      cursorColor: AppColores.primary,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: palette.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'ABC123',
        hintStyle: TextStyle(
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
          color: palette.textSecondary.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(Icons.pin_outlined, color: palette.textSecondary),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: conError ? AppColores.error : palette.grey300,
            width: conError ? 1.8 : 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: conError ? AppColores.error : AppColores.primary,
            width: 1.8,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.grey200),
        ),
      ),
    );
  }

  Widget _barraBotones() {
    final palette = context.palette;
    final isBusy = _guardando || _activando;
    final esActivo = _tipoActivo == _tipo;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: isBusy ? null : _guardarDatos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.textPrimary,
                    side: BorderSide(color: palette.grey300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Guardar',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _activarVehiculo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColores.buttonPrimary
                        .withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _activando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.black,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            esActivo
                                ? 'Actualizar ${_tipo.label.toLowerCase()}'
                                : 'Usar ${_tipo.label.toLowerCase()}',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;
    // "del carro" / "de la moto".
    final delTipo = _tipo == VehicleType.moto ? 'de la moto' : 'del carro';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Mis vehículos'),
      bottomNavigationBar: _cargando ? null : _barraBotones(),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _titulo(
                          'Tus vehículos',
                          'Registra carro y moto por separado. Solo recibes '
                              'solicitudes del que tengas en uso.',
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _tipoCard(
                                VehicleType.carro,
                                Icons.directions_car_filled_rounded,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _tipoCard(
                                VehicleType.moto,
                                Icons.two_wheeler_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        _titulo(
                          'Foto $delTipo',
                          'De lado o de frente, con la placa visible y buena '
                              'luz. El pasajero la verá para reconocerte.',
                        ),
                        _foto(),
                        _error(_errorFoto),
                        const SizedBox(height: 26),
                        _titulo(
                          'Placa $delTipo',
                          'Tal como aparece en el vehículo, sin espacios ni '
                              'guiones.',
                        ),
                        _campoPlaca(),
                        _error(_errorPlaca),
                        const SizedBox(height: 26),
                        CamposModeloColor(
                          // Un juego de controllers por tipo: la key evita
                          // que el cambio carro↔moto reutilice el estado.
                          key: ValueKey(_tipo),
                          modeloController: _modelos[_tipo]!,
                          colorController: _colores[_tipo]!,
                          tipo: _tipo.label.toLowerCase(),
                          errorModelo: _errorModelo,
                          errorColor: _errorColor,
                          enabled: !_guardando && !_activando,
                          onChanged: () => setState(() {
                            _errorModelo = null;
                            _errorColor = null;
                          }),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: acentoMarca(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '"Guardar" registra la foto y la placa sin '
                                'cambiar el vehículo en uso. "Usar" lo guarda '
                                'y lo pone en uso para recibir viajes.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
