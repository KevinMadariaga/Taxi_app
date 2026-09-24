import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/services/image_upload_service.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Pantalla para que un cliente complete su registro como conductor:
/// foto de perfil, foto del vehículo y placa. Al guardar, sube las imágenes
/// a Storage, persiste los datos en `usuarios/{uid}` y navega a [InicioConductor]
/// mostrando el modal de bienvenida.
class CompletarRegistroConductorView extends StatefulWidget {
  const CompletarRegistroConductorView({super.key});

  @override
  State<CompletarRegistroConductorView> createState() =>
      _CompletarRegistroConductorViewState();
}

class _CompletarRegistroConductorViewState
    extends State<CompletarRegistroConductorView> {
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _cropper = const ImageCropperService();
  late final ImageUploadService _imageUploadService = ImageUploadService();
  final TextEditingController _placaController = TextEditingController();

  XFile? _fotoVehiculo;
  String? _fotoExistenteUrl;
  String? _fotoVehiculoExistenteUrl;
  VehicleType _tipoVehiculo = VehicleType.carro;
  bool _guardando = false;
  String? _errorFoto;
  String? _errorPlaca;

  @override
  void initState() {
    super.initState();
    _cargarDatosCliente();
  }

  Future<void> _cargarDatosCliente() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await UserDataService().getUsuario(uid);
      if (data == null || !mounted) return;
      setState(() {
        _fotoExistenteUrl = (data['foto'] ?? data['fotoUrl'] ?? '').toString();
        _fotoVehiculoExistenteUrl = (data['fotoVehiculo'] ?? '').toString();
        final placa = (data['placa'] ?? '').toString();
        if (placa.isNotEmpty) _placaController.text = placa;
        final tipo = (data['tipoVehiculo'] ?? '').toString().toLowerCase();
        if (tipo == 'moto') {
          _tipoVehiculo = VehicleType.moto;
        } else if (tipo == 'carro') {
          _tipoVehiculo = VehicleType.carro;
        }
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'completar_registro_conductor_view');
    }
  }

  @override
  void dispose() {
    _placaController.dispose();
    super.dispose();
  }

  Future<ImageSource?> _elegirFuenteImagen() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageVehiculo() async {
    try {
      final source = await _elegirFuenteImagen();
      if (source == null) return;

      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;

      final cropped = await _cropper.cropVehicleImage(sourcePath: picked.path);
      if (cropped == null) return; // canceló el ajuste

      setState(() {
        _fotoVehiculo = XFile(cropped.path);
        _errorFoto = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error seleccionando imagen: $e')));
    }
  }

  Future<String> _subirImagen(XFile file, String campo, String uid) async {
    final path =
        'usuarios/$uid/${campo}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _imageUploadService.uploadFile(
      file: File(file.path),
      storagePath: path,
    );
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final placa = _placaController.text.trim();
    final tieneFotoVehiculo =
        _fotoVehiculo != null ||
        (_fotoVehiculoExistenteUrl != null &&
            _fotoVehiculoExistenteUrl!.isNotEmpty);
    // Errores bajo cada dato (no en un snackbar que tapa el botón): se
    // marcan los dos a la vez para que el usuario vea todo lo que falta.
    setState(() {
      _errorFoto = tieneFotoVehiculo ? null : 'Agrega la foto de tu vehículo.';
      _errorPlaca = placa.isEmpty
          ? 'Escribe la placa de tu vehículo.'
          : placa.length < 5
          ? 'La placa parece incompleta (ej. ABC123).'
          : null;
    });
    if (_errorFoto != null || _errorPlaca != null) {
      HapticFeedback.mediumImpact();
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotoExistenteUrl ?? '';
      final vehUrl = _fotoVehiculo != null
          ? await _subirImagen(_fotoVehiculo!, 'fotoVehiculo', uid)
          : _fotoVehiculoExistenteUrl!;

      await UserDataService().guardarSolicitudConductor(
        uid: uid,
        foto: fotoUrl,
        fotoVehiculo: vehUrl,
        placa: placa,
        tipoVehiculo: _tipoVehiculo.firestoreKey,
      );

      // El push al admin ya no lo manda el cliente (auditoría de seguridad:
      // `AdminFcmService` usaba la server key legacy de FCM repartida a
      // todos los dispositivos vía Remote Config). Lo dispara
      // `onSolicitudActivacionConductor` en functions/index.js al ver
      // `solicitudConductor: true` en Firestore.

      // Sincronizar rol en caché para que al reiniciar abra como conductor.
      await SessionHelper.updateRole('conductor');

      // Solo notificaciones + ubicación en primer plano acá. El permiso de
      // ubicación en segundo plano se pide después, recién cuando llega una
      // solicitud y el conductor toca "Aceptar" (ver
      // `_ensureBackgroundLocationForTrip` en `InicioConductorView`) — no
      // hace falta interrumpir el registro con el diálogo nativo "Permitir
      // siempre" antes de que haya un viaje real que trackear.
      await PermissionsHelper.requestAllPermissions();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const InicioConductor(mostrarBienvenida: true),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarError('No se pudo guardar el registro: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColores.error),
    );
  }

  Widget _tipoCard(VehicleType tipo, IconData icon) {
    final palette = context.palette;
    final sel = _tipoVehiculo == tipo;
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
        onTap: _guardando ? null : () => setState(() => _tipoVehiculo = tipo),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
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

  Widget _fotoVehiculoWidget() {
    final palette = context.palette;
    final existente = _fotoVehiculoExistenteUrl ?? '';
    final tieneFoto = _fotoVehiculo != null || existente.isNotEmpty;

    final Widget contenido;
    if (_fotoVehiculo != null) {
      contenido = Image.file(
        File(_fotoVehiculo!.path),
        fit: BoxFit.cover,
        cacheWidth: 900,
      );
    } else if (existente.isNotEmpty) {
      contenido = CachedNetworkImage(
        imageUrl: existente,
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
        onTap: _guardando ? null : _pickImageVehiculo,
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

  Widget _campoPlaca() {
    final palette = context.palette;
    final conError = _errorPlaca != null;
    return TextField(
      controller: _placaController,
      enabled: !_guardando,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(7),
        TextInputFormatter.withFunction(
          (_, nuevo) => nuevo.copyWith(text: nuevo.text.toUpperCase()),
        ),
      ],
      onChanged: (_) {
        if (_errorPlaca != null) setState(() => _errorPlaca = null);
      },
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.05 : 32.0;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Ser conductor'),
      bottomNavigationBar: BarraAccionInferior(
        texto: 'Enviar registro',
        icono: Icons.send_rounded,
        cargando: _guardando,
        onPressed: _guardar,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColores.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.local_taxi_rounded,
                      color: acentoMarca(context),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Registra tu vehículo',
                    style: TextStyle(
                      fontSize: esMovil ? 25 : 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Un administrador revisará tus datos y activará tu '
                    'membresía para que empieces a recibir viajes.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _titulo(
                    '¿Qué conduces?',
                    'Solo verás solicitudes de pasajeros para ese tipo de '
                        'vehículo.',
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
                    'Foto del vehículo',
                    'De lado o de frente, con la placa visible y buena luz. '
                        'El pasajero la verá para reconocerte.',
                  ),
                  _fotoVehiculoWidget(),
                  _error(_errorFoto),
                  const SizedBox(height: 26),
                  _titulo(
                    'Placa',
                    'Tal como aparece en el vehículo, sin espacios ni '
                        'guiones.',
                  ),
                  _campoPlaca(),
                  _error(_errorPlaca),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
