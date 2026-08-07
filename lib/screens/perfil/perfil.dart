import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/configuracion_aplicacion_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/completar_registro_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/membresia_detalle_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/cambiar_vehiculo_view.dart';
import 'package:taxi_app/screens/perfil/informacion_perfil_view.dart';
import 'package:taxi_app/screens/perfil/editar_perfil.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

class PaginaPerfilUsuario extends StatefulWidget {
  final String tipoUsuario; // 'cliente' o 'conductor'

  const PaginaPerfilUsuario({super.key, required this.tipoUsuario});

  @override
  State<PaginaPerfilUsuario> createState() => _PaginaPerfilUsuarioState();
}

class _PaginaPerfilUsuarioState extends State<PaginaPerfilUsuario> {
  bool _guardando = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserDataService _userDataService = UserDataService();

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Map<String, dynamic>? userData;
  File? _cachedImageFile;
  File? _cachedVehicleFile;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final user = _auth.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      if (mounted) setState(() => userData = <String, dynamic>{});
      return;
    }

    // 1) y 2): usuarios/{uid} + fallback a colecciones legacy (conductores
    // gestionados por admin guardan su perfil en `conductores`) resueltos en
    // el repositorio.
    final data = await _userDataService.getPerfilConFallback(uid);

    // 3) Fallback final a la cuenta de Firebase Auth.
    data.putIfAbsent('nombre', () => user?.displayName ?? '');
    data.putIfAbsent('email', () => user?.email ?? '');
    if ((data['foto'] ?? '').toString().trim().isEmpty &&
        (data['fotoUrl'] ?? '').toString().trim().isEmpty) {
      final photo = user?.photoURL;
      if (photo != null && photo.isNotEmpty) data['foto'] = photo;
    }

    if (!mounted) return;
    setState(() => userData = data);

    // Preparar caché de imagen: usar imagen local si existe, sino descargarla.
    try {
      final fotoUrl = (data['foto'] ?? data['fotoUrl'])?.toString();
      await _loadCachedImageForUid(uid, fotoUrl);
      final vehUrl = data['fotoVehiculo']?.toString();
      await _loadCachedVehicleImageForUid(uid, vehUrl);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  Future<void> _guardarCambios(Map<String, dynamic> nuevosDatos) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _guardando = false);
      return;
    }
    await _userDataService.actualizarDatosUsuario(uid, nuevosDatos);
    // Guardar nombre en caché si se actualizó
    try {
      final n = nuevosDatos['nombre']?.toString();
      if (n != null && n.trim().isNotEmpty) {
        await SessionHelper.saveCachedName(n.trim());
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
    _cargarDatos();
    // Mensaje de 'Datos guardados' eliminado por solicitud
    setState(() => _guardando = false);
  }

  Future<File> _cacheFileForUid(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/profile_$uid.jpg';
    return File(path);
  }

  Future<void> _loadCachedImageForUid(String uid, String? fotoUrl) async {
    try {
      final file = await _cacheFileForUid(uid);
      if (file.existsSync()) {
        if (mounted) {
          setState(() {
            _cachedImageFile = file;
          });
        }
        return;
      }
      if (fotoUrl == null || fotoUrl.isEmpty) return;
      await _downloadAndSaveImage(fotoUrl, uid);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  Future<void> _downloadAndSaveImage(String url, String uid) async {
    try {
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return;
      final file = await _cacheFileForUid(uid);
      final iosink = file.openWrite();
      await response.pipe(iosink);
      await iosink.flush();
      await iosink.close();
      // Evict any existing cached image for this file path so Flutter reloads it
      try {
        await FileImage(file).evict();
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'perfil');
      }

      if (mounted) {
        setState(() {
          _cachedImageFile = file;
        });
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  Future<File> _vehicleCacheFileForUid(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/vehicle_$uid.jpg';
    return File(path);
  }

  Future<void> _loadCachedVehicleImageForUid(
    String uid,
    String? fotoVehiculoUrl,
  ) async {
    try {
      final file = await _vehicleCacheFileForUid(uid);
      if (file.existsSync()) {
        if (mounted) {
          setState(() {
            _cachedVehicleFile = file;
          });
        }
        return;
      }
      if (fotoVehiculoUrl == null || fotoVehiculoUrl.isEmpty) return;
      await _downloadAndSaveVehicleImage(fotoVehiculoUrl, uid);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  Future<void> _downloadAndSaveVehicleImage(String url, String uid) async {
    try {
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return;
      final file = await _vehicleCacheFileForUid(uid);
      final iosink = file.openWrite();
      await response.pipe(iosink);
      await iosink.flush();
      await iosink.close();
      try {
        await FileImage(file).evict();
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'perfil');
      }
      if (mounted) {
        setState(() {
          _cachedVehicleFile = file;
        });
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  Future<void> _deleteCachedVehicleFile(String uid) async {
    try {
      final file = await _vehicleCacheFileForUid(uid);
      if (file.existsSync()) {
        try {
          await FileImage(file).evict();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'perfil');
        }
        await file.delete();
      }
      if (mounted) setState(() => _cachedVehicleFile = null);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
  }

  /// Cambia el rol en Firestore y solo entonces navega.
  ///
  /// Antes las dos tarjetas de cambio de rol eran fire-and-forget: llamaban a
  /// `UserDataService` sin `await`, actualizaban la caché local de
  /// `SessionHelper` y navegaban. Si la escritura fallaba, la app abría el
  /// home del otro rol con el rol viejo en el servidor y sin ningún aviso —
  /// en el caso conductor eso deja la lista de solicitudes vacía para
  /// siempre, porque las reglas de Firestore la filtran por `rol`.
  Future<void> _cambiarRol({
    required String rol,
    required Future<void> Function(String uid) escribir,
    required Widget Function() destino,
    bool rootNavigator = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _guardando) return;

    final navigator = Navigator.of(context, rootNavigator: rootNavigator);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _guardando = true);
    try {
      await escribir(uid);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil: cambiar rol a $rol');
      if (!mounted) return;
      setState(() => _guardando = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo cambiar de modo. Revisa tu conexión e inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }

    // Solo con la escritura confirmada: caché local y navegación.
    SessionHelper.updateRole(rol);
    if (!mounted) return;
    setState(() => _guardando = false);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destino()),
      (route) => false,
    );
  }

  void _mostrarDialogoEditar() {
    final nombreController = TextEditingController(
      text: userData?['nombre'] ?? '',
    );
    final apellidoController = TextEditingController(
      text: userData?['apellido'] ?? '',
    );
    final telefonoController = TextEditingController(
      text: userData?['telefono'] ?? '',
    );
    final placaController = TextEditingController(
      text: userData?['placa'] ?? '',
    );
    final esConductor = widget.tipoUsuario == 'conductor';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditarPerfilScreen(
          nombreController: nombreController,
          apellidoController: apellidoController,
          telefonoController: telefonoController,
          placaController: placaController,
          esConductor: esConductor,
          selectedImage: _cachedImageFile,
          selectedVehicleImage: _cachedVehicleFile,
          onImageChanged: (file) async {
            final uid = _auth.currentUser?.uid;
            if (uid != null && file != null) {
              final cacheFile = await _cacheFileForUid(uid);
              await file.copy(cacheFile.path);
              try {
                await FileImage(cacheFile).evict();
              } catch (e, st) {
                ErrorReporter.report(e, st, reason: 'perfil');
              }
              setState(() {
                _cachedImageFile = cacheFile;
              });
            }
          },
          onVehicleImageChanged: (file) async {
            final uid = _auth.currentUser?.uid;
            if (uid != null && file != null) {
              final cacheFile = await _vehicleCacheFileForUid(uid);
              await file.copy(cacheFile.path);
              try {
                await FileImage(cacheFile).evict();
              } catch (e, st) {
                ErrorReporter.report(e, st, reason: 'perfil');
              }
              setState(() {
                _cachedVehicleFile = cacheFile;
              });
            }
          },
          onSave: (datos) async {
            // El caché local ya quedó actualizado (copia + evict) en
            // onImageChanged/onVehicleImageChanged con los bytes recién
            // subidos; no hace falta borrar y volver a descargar de Storage.
            await _guardarCambios(datos);
          },
        ),
      ),
    );
  }

  Widget _buildSerConductorCard() {
    // Si ya tiene datos de conductor guardados (placa + foto vehículo), solo
    // cambia de vista a InicioConductor sin volver a registrar.
    final placa = (userData?['placa'] ?? '').toString().trim();
    final fotoVeh = (userData?['fotoVehiculo'] ?? '').toString().trim();
    final yaRegistrado = placa.isNotEmpty && fotoVeh.isNotEmpty;

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: ListTile(
        leading: Icon(Icons.local_taxi, color: AppColores.primary),
        title: Text(
          yaRegistrado ? 'Modo conductor' : 'Ser conductor',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          yaRegistrado
              ? 'Entra como conductor'
              : 'Completa tu registro y empieza a recibir viajes',
        ),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 0.5),
        ),
        onTap: () {
          if (yaRegistrado) {
            // Cambiar rol a conductor (Firestore + caché) para que al
            // reiniciar la app abra como conductor.
            _cambiarRol(
              rol: 'conductor',
              escribir: _userDataService.cambiarRolAConductor,
              destino: () => const InicioConductor(),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CompletarRegistroConductorView(),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildVolverClienteCard() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: ListTile(
        leading: Icon(Icons.person_outline, color: AppColores.primary),
        title: const Text(
          'Volver a ser cliente',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Usa la app como cliente'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 0.5),
        ),
        onTap: () {
          // rol cliente + quitar solicitud → retira notif del admin.
          _cambiarRol(
            rol: 'cliente',
            escribir: _userDataService.volverACliente,
            destino: () => const HomeClienteView(),
            rootNavigator: true,
          );
        },
      ),
    );
  }

  Widget _buildInfoPerfilCard() {
    final esConductor =
        widget.tipoUsuario == 'conductor' ||
        (userData?['rol'] ?? '').toString().toLowerCase() == 'conductor';
    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final uid = _auth.currentUser?.uid;
          if (uid == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InformacionPerfilView(
                uid: uid,
                esConductor: esConductor,
                onEditar: _mostrarDialogoEditar,
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 4),
            vertical: ResponsiveHelper.hp(context, 1.5),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_circle_outlined,
                color: AppColores.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información del perfil',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Datos personales y vehículos',
                      style: TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColores.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCambiarVehiculoCard() {
    final tipo = (userData?['tipoVehiculo'] ?? '').toString().toLowerCase();
    final tipoLabel = tipo == 'moto'
        ? 'Moto'
        : tipo == 'carro'
        ? 'Carro'
        : '—';
    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final cambiado = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const CambiarVehiculoView()),
          );
          if (cambiado == true) await _cargarDatos();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 4),
            vertical: ResponsiveHelper.hp(context, 1.5),
          ),
          child: Row(
            children: [
              Icon(
                tipo == 'moto'
                    ? Icons.two_wheeler_rounded
                    : Icons.directions_car_filled_rounded,
                color: AppColores.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cambiar de vehículo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Actual: $tipoLabel · Cambia tipo, foto y placa',
                      style: const TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColores.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembresiaConductorCard() {
    final activa =
        (userData?['membresia'] ?? '').toString().toLowerCase() == 'activa';
    final dias = userData?['membresiaDias'];
    final venceTs = userData?['membresiaVence'];
    String? venceStr;
    int? diasRestantes;
    if (venceTs is Timestamp) {
      final d = venceTs.toDate();
      venceStr =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      diasRestantes = d.difference(DateTime.now()).inDays;
      if (diasRestantes < 0) diasRestantes = 0;
    }
    final color = activa ? AppColores.success : AppColores.error;

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final uid = _auth.currentUser?.uid;
          if (uid == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MembresiaDetalleView(uid: uid),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 4),
            vertical: ResponsiveHelper.hp(context, 1.5),
          ),
          child: Row(
            children: [
              Icon(
                activa ? Icons.verified : Icons.cancel,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activa ? 'Estás activo' : 'No estás activo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activa
                          ? (dias != null
                                ? 'Membresía activa · $dias días'
                                      '${diasRestantes != null ? ' · faltan $diasRestantes días' : ''}'
                                      '${venceStr != null ? ' · vence $venceStr' : ''}'
                                : 'Membresía activa')
                          : 'Activa tu membresía para recibir viajes',
                      style: const TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toca para más detalles',
                      style: TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColores.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreCompleto = [
      (userData?['nombre'] ?? '').toString().trim(),
      (userData?['apellido'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).join(' ').trim();
    final nombre = nombreCompleto.isEmpty ? 'Usuario' : nombreCompleto;
    final fotoUrl = (userData?['foto'] ?? userData?['fotoUrl'] ?? '')
        .toString();

    // Responsive sizes based on screen dimensions and safe clamps
    final screenWidth = MediaQuery.of(context).size.width;

    final double appBarFontSize = (screenWidth * 0.05).clamp(18.0, 22.0);
    double computedNameFontSize = (screenWidth * 0.06).clamp(18.0, 26.0);
    double avatarRadius = (screenWidth * 0.14).clamp(36.0, 70.0);
    final double avatarIconSize = (avatarRadius * 0.9).clamp(28.0, 56.0);

    // Adjust name font size for very long names
    if (nombre.length > 18 && nombre.length <= 26) {
      computedNameFontSize = math.max(18.0, computedNameFontSize * 0.9);
    } else if (nombre.length > 26) {
      computedNameFontSize = math.max(16.0, computedNameFontSize * 0.8);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.tipoUsuario == 'cliente'
            ? false
            : true,
        title: Text('Perfil', style: TextStyle(fontSize: appBarFontSize)),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConfiguracionAplicacionView(),
                ),
              );
            },
          ),
        ],
      ),
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: ResponsiveHelper.wp(context, 4),
                        right: ResponsiveHelper.wp(context, 4),
                        top: ResponsiveHelper.hp(context, 0.5),
                        bottom: ResponsiveHelper.hp(context, 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                          Center(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: avatarRadius,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage:
                                      _cachedImageFile != null &&
                                          _cachedImageFile!.existsSync()
                                      ? FileImage(_cachedImageFile!)
                                            as ImageProvider
                                      : (fotoUrl.isNotEmpty
                                            ? NetworkImage(fotoUrl)
                                            : null),
                                  child:
                                      (_cachedImageFile == null ||
                                              !(_cachedImageFile
                                                      ?.existsSync() ??
                                                  false)) &&
                                          fotoUrl.isEmpty
                                      ? Icon(
                                          Icons.person,
                                          size: avatarIconSize,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                if (_isUploading)
                                  Positioned(
                                    bottom: -6,
                                    child: SizedBox(
                                      width: avatarRadius * 1.8,
                                      child: LinearProgressIndicator(
                                        value: _uploadProgress,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.hp(context, 2)),
                          Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: ResponsiveHelper.wp(context, 80),
                              ),
                              child: Text(
                                nombre.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: computedNameFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                          if (widget.tipoUsuario == 'conductor') ...[
                            // Conductor: membresía (estás activo / vence / toca
                            // para más detalles) primero → información del perfil
                            // → cambiar vehículo → volver a ser cliente.
                            _buildMembresiaConductorCard(),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                            _buildInfoPerfilCard(),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                            _buildCambiarVehiculoCard(),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                            _buildVolverClienteCard(),
                          ] else ...[
                            // Cliente: información del perfil + opción de
                            // convertirse en conductor.
                            _buildInfoPerfilCard(),
                            if (widget.tipoUsuario == 'cliente' ||
                                (userData?['rol'] ?? '')
                                        .toString()
                                        .toLowerCase() ==
                                    'cliente') ...[
                              SizedBox(
                                height: ResponsiveHelper.hp(context, 0.4),
                              ),
                              _buildSerConductorCard(),
                            ],
                          ],
                          SizedBox(height: ResponsiveHelper.hp(context, 1.4)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
