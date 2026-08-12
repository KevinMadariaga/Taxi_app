import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/services/admin_fcm_service.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/services/image_upload_service.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/widgets/boton.dart';
import 'package:taxi_app/widgets/flip_preview_view.dart';
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
  final ImageUploadService _imageUploadService = ImageUploadService();
  final TextEditingController _placaController = TextEditingController();

  XFile? _fotoPerfil;
  XFile? _fotoVehiculo;
  String? _fotoExistenteUrl;
  String? _fotoVehiculoExistenteUrl;
  VehicleType _tipoVehiculo = VehicleType.carro;
  bool _guardando = false;

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

  Future<void> _pickImage({required bool esVehiculo}) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;

      File sourceFile = File(picked.path);
      if (!esVehiculo) {
        if (!mounted) return;
        final flipped = await showFlipPreview(context, imageFile: sourceFile);
        if (flipped == null) return;
        sourceFile = flipped;
      }

      // Abrir editor para recortar/mover la foto (mismo flujo que registro cliente).
      final cropped = esVehiculo
          ? await _cropper.cropVehicleImage(sourcePath: sourceFile.path)
          : await _cropper.cropProfileImage(sourcePath: sourceFile.path);
      if (cropped == null) return; // canceló el ajuste

      setState(() {
        final xf = XFile(cropped.path);
        if (esVehiculo) {
          _fotoVehiculo = xf;
        } else {
          _fotoPerfil = xf;
        }
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
    final tieneFotoPerfil =
        _fotoPerfil != null ||
        (_fotoExistenteUrl != null && _fotoExistenteUrl!.isNotEmpty);
    if (!tieneFotoPerfil) {
      _mostrarError('Agrega tu foto de perfil.');
      return;
    }
    final tieneFotoVehiculo =
        _fotoVehiculo != null ||
        (_fotoVehiculoExistenteUrl != null &&
            _fotoVehiculoExistenteUrl!.isNotEmpty);
    if (!tieneFotoVehiculo) {
      _mostrarError('Agrega la foto de tu vehículo.');
      return;
    }
    if (placa.isEmpty) {
      _mostrarError('Ingresa el número de placa.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotoPerfil != null
          ? await _subirImagen(_fotoPerfil!, 'foto', uid)
          : _fotoExistenteUrl!;
      final vehUrl = _fotoVehiculo != null
          ? await _subirImagen(_fotoVehiculo!, 'fotoVehiculo', uid)
          : _fotoVehiculoExistenteUrl!;

      final nombre =
          (FirebaseAuth.instance.currentUser?.displayName ?? 'Conductor')
              .toString();

      await UserDataService().guardarSolicitudConductor(
        uid: uid,
        foto: fotoUrl,
        fotoVehiculo: vehUrl,
        placa: placa,
        tipoVehiculo: _tipoVehiculo.firestoreKey,
      );

      // Notificar al admin que hay un nuevo conductor pendiente de revisión.
      AdminFcmService.instance
          .sendToAllAdmins(
            title: 'Nuevo conductor registrado',
            body: '$nombre quiere activar el servicio, revisa.',
            type: 'solicitud_conductor',
          )
          .ignore();

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
    final sel = _tipoVehiculo == tipo;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _tipoVehiculo = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: sel
              ? AppColores.primary.withValues(alpha: 0.12)
              : AppColores.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppColores.primary : AppColores.grey300,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: sel ? const Color(0xFFB38F00) : AppColores.grey600,
            ),
            const SizedBox(height: 8),
            Text(
              tipo.label,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                fontSize: 15,
                color: AppColores.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa el registro de conductor'),
        backgroundColor: AppColores.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () => _pickImage(esVehiculo: false),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 65,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: _fotoPerfil != null
                            ? FileImage(File(_fotoPerfil!.path))
                                  as ImageProvider
                            : (_fotoExistenteUrl != null &&
                                  _fotoExistenteUrl!.isNotEmpty)
                            ? NetworkImage(_fotoExistenteUrl!)
                            : null,
                        child:
                            (_fotoPerfil == null &&
                                (_fotoExistenteUrl == null ||
                                    _fotoExistenteUrl!.isEmpty))
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 32,
                                    color: Colors.black54,
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Foto de perfil',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              )
                            : null,
                      ),
                      // Badge cámara: siempre visible para indicar que se puede cambiar.
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColores.buttonPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 17,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Foto del vehículo',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _pickImage(esVehiculo: true),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 170,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        child: _fotoVehiculo != null
                            ? Image.file(
                                File(_fotoVehiculo!.path),
                                fit: BoxFit.cover,
                              )
                            : (_fotoVehiculoExistenteUrl != null &&
                                  _fotoVehiculoExistenteUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: _fotoVehiculoExistenteUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 780,
                                memCacheHeight: 340,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColores.primary,
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 40,
                                        color: Colors.black38,
                                      ),
                                    ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.directions_car,
                                    size: 40,
                                    color: Colors.black54,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Agregar foto del vehículo',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () => _pickImage(esVehiculo: true),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColores.buttonPrimary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '¿Qué conduces?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 24),
              TextField(
                controller: _placaController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Placa del vehículo',
                  prefixIcon: Icon(Icons.confirmation_number),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
              CustomButton(
                text: _guardando ? 'Guardando...' : 'Guardar',
                isLoading: _guardando,
                onPressed: _guardando ? null : _guardar,
                height: 50,
                fontSize: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
