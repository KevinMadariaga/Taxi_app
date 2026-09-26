import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/calificacion_cliente/presentacion/viewmodels/calificaciones_clientes_viewmodel.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
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
import 'package:taxi_app/core/validators/vehiculo_validator.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

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

  Map<String, dynamic>? userData;

  /// Viajes completados (null mientras carga o si falla la consulta).
  int? _viajes;
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
    unawaited(_contarViajes(uid));

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
    // Sincronizar displayName de Auth: sin esto quedaba congelado con el
    // nombre del proveedor (Google/Apple) para siempre, y lectores como el
    // chat de soporte o esta misma pantalla (fallback sin red) seguían
    // mostrando el nombre viejo aunque el usuario ya hubiera editado el suyo.
    try {
      final nombre = nuevosDatos['nombre']?.toString().trim() ?? '';
      final apellido = nuevosDatos['apellido']?.toString().trim() ?? '';
      final nombreCompleto = '$nombre $apellido'.trim();
      if (nombreCompleto.isNotEmpty) {
        final user = _auth.currentUser;
        if (user != null && user.displayName != nombreCompleto) {
          await user.updateDisplayName(nombreCompleto);
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil');
    }
    await _cargarDatos();
    // Mensaje de 'Datos guardados' eliminado por solicitud
    if (mounted) setState(() => _guardando = false);
  }

  Future<void> _contarViajes(String uid) async {
    final campo = widget.tipoUsuario == 'conductor'
        ? 'conductor.id'
        : 'cliente.id';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('solicitudes')
          .where(campo, isEqualTo: uid)
          .get();
      final completados = snap.docs.where((d) {
        final estado = SolicitudEstado.normalize(
          (d.data()['estado'] ?? d.data()['status'] ?? '').toString(),
        );
        return estado == SolicitudEstado.completado;
      }).length;
      if (mounted) setState(() => _viajes = completados);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'perfil: contar viajes');
    }
  }

  /// Promedio del conductor que acumula la Cloud Function en su
  /// `usuarios/{uid}`; null sin calificaciones.
  double? get _promedioConductor {
    final d = userData;
    if (d == null) return null;
    final total = num.tryParse('${d['totalCalificaciones'] ?? 0}') ?? 0;
    if (total <= 0) return null;
    return num.tryParse(
      '${d['calificacionConductor'] ?? d['calificacionPromedio'] ?? d['calificacion']}',
    )?.toDouble();
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
    final modeloController = TextEditingController(
      text: (userData?['modeloVehiculo'] ?? '').toString(),
    );
    final colorController = TextEditingController(
      text: (userData?['colorVehiculo'] ?? '').toString(),
    );
    final esConductor = widget.tipoUsuario == 'conductor';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditarPerfilScreen(
          nombreController: nombreController,
          apellidoController: apellidoController,
          telefonoController: telefonoController,
          placaController: placaController,
          modeloController: modeloController,
          colorController: colorController,
          tipoVehiculo:
              (userData?['tipoVehiculo'] ?? '').toString().toLowerCase() ==
                  'moto'
              ? 'moto'
              : 'carro',
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

  bool get _esConductor =>
      widget.tipoUsuario == 'conductor' ||
      (userData?['rol'] ?? '').toString().toLowerCase() == 'conductor';

  void _abrirInformacionPerfil() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InformacionPerfilView(
          uid: uid,
          esConductor: _esConductor,
          onEditar: _mostrarDialogoEditar,
        ),
      ),
    );
  }

  void _abrirConfiguracion() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracionAplicacionView()),
    );
  }

  Future<void> _abrirCambiarVehiculo() async {
    final cambiado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CambiarVehiculoView()),
    );
    if (cambiado == true) await _cargarDatos();
  }

  void _abrirMembresia() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MembresiaDetalleView(uid: uid)));
  }

  void _serConductor() {
    // Si ya tiene datos de conductor guardados (placa + foto vehículo), solo
    // cambia de vista a InicioConductor sin volver a registrar.
    if (_yaRegistradoComoConductor) {
      // Cambiar rol a conductor (Firestore + caché) para que al reiniciar la
      // app abra como conductor.
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
  }

  void _volverACliente() {
    // rol cliente + quitar solicitud → retira notif del admin.
    _cambiarRol(
      rol: 'cliente',
      escribir: _userDataService.volverACliente,
      destino: () => const HomeClienteView(),
      rootNavigator: true,
    );
  }

  bool get _yaRegistradoComoConductor =>
      (userData?['placa'] ?? '').toString().trim().isNotEmpty &&
      (userData?['fotoVehiculo'] ?? '').toString().trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.05 : 32.0;
    final esVistaConductor = widget.tipoUsuario == 'conductor';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(
        context,
        titulo: 'Mi perfil',
        automaticallyImplyLeading: widget.tipoUsuario != 'cliente',
      ),
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 28),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: esMovil ? 560 : 600,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _EncabezadoPerfil(
                            nombre: _nombreVisible,
                            esConductor: esVistaConductor,
                            uid: _auth.currentUser?.uid,
                            viajes: _viajes,
                            promedioConductor: _promedioConductor,
                            imagenLocal: _cachedImageFile,
                            fotoUrl:
                                (userData?['foto'] ??
                                        userData?['fotoUrl'] ??
                                        '')
                                    .toString(),
                            avatarSize: esMovil ? 96 : 116,
                          ),
                          const SizedBox(height: 22),
                          if (esVistaConductor) ...[
                            _TarjetaMembresia(
                              data: userData!,
                              onTap: _abrirMembresia,
                            ),
                            const SizedBox(height: 22),
                          ],
                          SeccionAgrupada(
                            titulo: 'Cuenta',
                            children: [
                              FilaOpcion(
                                titulo: 'Información del perfil',
                                subtitulo: esVistaConductor
                                    ? 'Datos personales y de tu vehículo'
                                    : 'Nombre, teléfono y foto',
                                onTap: _abrirInformacionPerfil,
                              ),
                            ],
                          ),
                          if (esVistaConductor) ...[
                            const SizedBox(height: 18),
                            SeccionAgrupada(
                              titulo: 'Vehículo',
                              children: [_opcionVehiculo()],
                            ),
                          ],
                          const SizedBox(height: 18),
                          SeccionAgrupada(
                            titulo: 'Modo de uso',
                            children: [
                              if (esVistaConductor)
                                FilaOpcion(
                                  icono: Icons.person_outline_rounded,
                                  titulo: 'Volver a ser cliente',
                                  subtitulo: 'Pide viajes como pasajero',
                                  onTap: _guardando ? null : _volverACliente,
                                )
                              else if (widget.tipoUsuario == 'cliente' ||
                                  (userData?['rol'] ?? '')
                                          .toString()
                                          .toLowerCase() ==
                                      'cliente')
                                FilaOpcion(
                                  icono: Icons.local_taxi_outlined,
                                  titulo: _yaRegistradoComoConductor
                                      ? 'Modo conductor'
                                      : 'Ser conductor',
                                  subtitulo: _yaRegistradoComoConductor
                                      ? 'Entra como conductor'
                                      : 'Regístrate y empieza a recibir viajes',
                                  destacado: !_yaRegistradoComoConductor,
                                  onTap: _guardando ? null : _serConductor,
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SeccionAgrupada(
                            titulo: 'Ajustes',
                            children: [
                              FilaOpcion(
                                icono: Icons.tune_rounded,
                                titulo: 'Configuración',
                                subtitulo:
                                    'Tema, notificaciones, legal y cuenta',
                                onTap: _abrirConfiguracion,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String get _nombreVisible {
    final completo = [
      (userData?['nombre'] ?? '').toString().trim(),
      (userData?['apellido'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).join(' ');
    return completo.isEmpty ? 'Usuario' : completo;
  }

  Widget _opcionVehiculo() {
    final tipo = (userData?['tipoVehiculo'] ?? '').toString().toLowerCase();
    final tipoLabel = switch (tipo) {
      'moto' => 'Moto',
      'carro' => 'Carro',
      _ => 'Sin definir',
    };
    final placa = (userData?['placa'] ?? '').toString().trim().toUpperCase();
    final detalle = [
      tipoLabel,
      VehiculoValidator.descripcion(
        userData?['modeloVehiculo']?.toString(),
        userData?['colorVehiculo']?.toString(),
      ),
      placa,
    ].where((p) => p.isNotEmpty).join(' · ');
    return FilaOpcion(
      icono: tipo == 'moto'
          ? Icons.two_wheeler_rounded
          : Icons.directions_car_outlined,
      titulo: 'Cambiar de vehículo',
      subtitulo: detalle,
      onTap: _guardando ? null : _abrirCambiarVehiculo,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EncabezadoPerfil extends StatelessWidget {
  const _EncabezadoPerfil({
    required this.nombre,
    required this.esConductor,
    required this.uid,
    required this.viajes,
    required this.promedioConductor,
    required this.imagenLocal,
    required this.fotoUrl,
    required this.avatarSize,
  });

  final String nombre;
  final bool esConductor;

  /// Del pasajero: para mostrarle la calificación que le dieron los
  /// conductores.
  final String? uid;
  final int? viajes;

  /// Del conductor (viene de su propio `usuarios/{uid}`). El del pasajero se
  /// lee de `calificaciones_clientes` vía [CalificacionesClientesViewModel].
  final double? promedioConductor;
  final File? imagenLocal;
  final String fotoUrl;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          _Avatar(archivo: imagenLocal, url: fotoUrl, size: avatarSize),
          const SizedBox(height: 14),
          Text(
            nombre,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                icono: esConductor
                    ? Icons.local_taxi_rounded
                    : Icons.person_rounded,
                texto: esConductor ? 'Conductor' : 'Pasajero',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _EstadisticasPerfil(
            viajes: viajes,
            promedio: esConductor
                ? promedioConductor
                : _promedioCliente(context, uid),
          ),
        ],
      ),
    );
  }
}

/// Foto de perfil decodificada al tamaño en pantalla (`cacheWidth`): una
/// foto de cámara a resolución completa ocupa decenas de MB en memoria para
/// pintar un círculo de ~100 px.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.archivo, required this.url, required this.size});

  final File? archivo;
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    Widget sinFoto() => ColoredBox(
      color: palette.grey200,
      child: Icon(
        Icons.person_rounded,
        size: size * 0.5,
        color: palette.textSecondary,
      ),
    );

    final Widget imagen;
    if (archivo != null) {
      imagen = Image.file(
        archivo!,
        fit: BoxFit.cover,
        cacheWidth: cache,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => sinFoto(),
      );
    } else if (url.isNotEmpty) {
      imagen = Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: cache,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => sinFoto(),
      );
    } else {
      imagen = sinFoto();
    }

    return Semantics(
      label: 'Foto de perfil',
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
            color: palette.surface,
          ),
          child: ClipOval(
            child: SizedBox.square(dimension: size, child: imagen),
          ),
        ),
      ),
    );
  }
}

double? _promedioCliente(BuildContext context, String? uid) {
  if (uid == null) return null;
  final CalificacionesClientesViewModel vm;
  try {
    vm = context.watch<CalificacionesClientesViewModel>();
  } on ProviderNotFoundException {
    return null;
  }
  final c = vm.de(uid);
  return (c != null && c.tieneCalificaciones) ? c.promedio : null;
}

/// "12 Viajes | ★4.8 Calificación". "–" mientras carga o sin datos.
class _EstadisticasPerfil extends StatelessWidget {
  const _EstadisticasPerfil({required this.viajes, required this.promedio});

  final int? viajes;
  final double? promedio;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: palette.borderSubtle),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Estadistica(
                valor: viajes?.toString() ?? '–',
                etiqueta: 'Viajes',
              ),
            ),
            VerticalDivider(width: 1, color: palette.borderSubtle),
            Expanded(
              child: _Estadistica(
                valor: promedio?.toStringAsFixed(1) ?? '–',
                etiqueta: 'Calificación',
                conEstrella: promedio != null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Estadistica extends StatelessWidget {
  const _Estadistica({
    required this.valor,
    required this.etiqueta,
    this.conEstrella = false,
  });

  final String valor;
  final String etiqueta;
  final bool conEstrella;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: '$etiqueta: $valor',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conEstrella)
                const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: AppColores.primary,
                ),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColores.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: AppColores.primary),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaMembresia extends StatelessWidget {
  const _TarjetaMembresia({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activa =
        (data['membresia'] ?? '').toString().toLowerCase() == 'activa';
    final dias = int.tryParse('${data['membresiaDias'] ?? ''}');
    final venceTs = data['membresiaVence'];
    String? venceStr;
    int? restantes;
    if (venceTs is Timestamp) {
      final d = venceTs.toDate();
      venceStr =
          '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
      restantes = d.difference(DateTime.now()).inDays.clamp(0, 9999);
    }
    final color = activa ? AppColores.success : AppColores.error;
    final progreso = activa && dias != null && dias > 0 && restantes != null
        ? (restantes / dias).clamp(0.0, 1.0)
        : null;

    return Material(
      color: Color.alphaBlend(color.withValues(alpha: 0.10), palette.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      activa
                          ? Icons.workspace_premium_rounded
                          : Icons.lock_clock_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activa ? 'Membresía activa' : 'Membresía inactiva',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activa
                              ? [
                                  if (restantes != null)
                                    'Te quedan $restantes días',
                                  if (venceStr != null) 'vence $venceStr',
                                ].join(' · ').ifEmpty('Puedes recibir viajes')
                              : 'Actívala para empezar a recibir viajes',
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
              if (progreso != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 6,
                    backgroundColor: color.withValues(alpha: 0.18),
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
