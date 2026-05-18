import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/data/solicitud_repository.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteDestinoView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/services/services.dart';

class Rutaclientedestinoviewmodel extends ChangeNotifier {
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // Servicio de mapas
  final MapService _mapService = const MapService();
  bool isLoadingRoute = false;

  /// Obtiene la polyline entre conductor y destino usando la API de direcciones.
  /// Si la API falla, retorna una línea recta entre ambos.
  Future<List<LatLng>> obtenerPolylineConductorDestino() async {
    if (latConductor == null ||
        lngConductor == null ||
        latDestino == null ||
        lngDestino == null) {
      return [];
    }
    isLoadingRoute = true;
    _safeNotify();
    try {
      final origen = LatLng(latConductor!, lngConductor!);
      final destino = LatLng(latDestino!, lngDestino!);
      return await _mapService.getRoutePolyline(origen, destino);
    } finally {
      isLoadingRoute = false;
      _safeNotify();
    }
  }

  double calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }

  CameraPosition? getCameraPerspective() {
    if (latConductor == null ||
        lngConductor == null ||
        latDestino == null ||
        lngDestino == null) {
      return null;
    }
    final from = LatLng(latConductor!, lngConductor!);
    final to = LatLng(latDestino!, lngDestino!);
    final bearing = calculateBearing(from, to);
    return CameraPosition(
      target: from,
      bearing: bearing,
      tilt: 0.0,
      zoom: 16.5,
    );
  }

  /// Calcula la distancia total de la polyline (en metros).
  double calcularDistanciaPolyline(List<LatLng> polyline) {
    return _mapService.calcularDistanciaPolyline(polyline);
  }

  /// Calcula el tiempo estimado (en segundos) entre conductor y destino usando la API.
  Future<int?> calcularTiempoEstimado() async {
    if (latConductor == null ||
        lngConductor == null ||
        latDestino == null ||
        lngDestino == null) {
      return null;
    }
    final origen = LatLng(latConductor!, lngConductor!);
    final destino = LatLng(latDestino!, lngDestino!);
    return await _mapService.calcularTiempoEstimado(origen, destino);
  }

  final SolicitudRepository _solicitudRepository = SolicitudRepository();
  StreamSubscription<Map<String, dynamic>?>? _conductorUbicacionSub;
  bool _navegandoAResumen = false;

  /// Escucha en tiempo real la ubicación del conductor y actualiza el ViewModel
  void escucharUbicacionConductor(String solicitudId) {
    _conductorUbicacionSub?.cancel();
    _conductorUbicacionSub = _solicitudRepository
        .conductorUbicacionStream(solicitudId)
        .listen((ubicacion) {
          if (ubicacion != null) {
            latConductor = (ubicacion['lat'] as num?)?.toDouble();
            lngConductor = (ubicacion['lng'] as num?)?.toDouble();
            _safeNotify();
          }
        });
  }

  // Tiempo estimado del viaje
  String _tiempoEstimado = '0 min';
  String get tiempoEstimado => _tiempoEstimado;

  // Método para actualizar el tiempo estimado
  void setTiempoEstimado(String tiempo) {
    _tiempoEstimado = tiempo;
    _safeNotify();
  }

  // Estado de solicitud
  StreamSubscription<DocumentSnapshot>? _solicitudStateSub;

  /// Id del usuario actual (cliente)
  String? get usuarioId => FirebaseAuth.instance.currentUser?.uid;

  // /// Mensajes no leídos por el usuario actual
  // int get mensajesPendientes {
  //   if (usuarioId == null || mensajes.isEmpty) return 0;
  //   return mensajes.where((m) => !(m.readBy?[usuarioId] ?? false) && m.senderId != usuarioId).length;
  // }
  // Polyline management
  List<LatLng> polylinePoints = [];
  int indiceActual = 0;

  // Chat (deshabilitado en esta clase)
  // final ChatService chatService = ChatService();
  // StreamSubscription<List<ChatMessage>>? _chatSub;
  // List<ChatMessage> mensajes = [];

  // Datos del conductor y cliente
  String nombreConductor = '';
  String fotoConductor = '';
  String placaVehiculo = '';
  String fotoVehiculo = '';
  double? latDestino;
  double? lngDestino;
  double? latConductor;
  double? lngConductor;

  // Estado del conductor
  String nombreConductorEstado = 'Conductor';
  String estado = 'Disponible';

  // Notificaciones unified
  final NotificacionesServicio _notificaciones =
      NotificacionesServicio.instance;

  /// Detecta si es la primera vez que se ingresa a la clase con el idSolicitud
  Future<bool> esPrimeraVezClase(String solicitudId) async {
    final activa = await SessionHelper.getActiveSolicitud();
    return activa == null || activa != solicitudId;
  }

  void escucharEstadoSolicitud(String solicitudId, BuildContext context) {
    _solicitudStateSub?.cancel();
    String? ultimoEstado;
    _solicitudStateSub = FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((doc) async {
          if (!doc.exists) return;
          final data = doc.data();
          final estado = data?['estado']?.toString().toLowerCase() ?? '';
          debugPrint('[RutaClienteViewModel] Estado escuchado: $estado');
          if (ultimoEstado != estado &&
              estado == 'completado' &&
              !_navegandoAResumen) {
            debugPrint(
              '[RutaClienteViewModel] Cambio detectado a "completado". Navegando a ResumenClienteView...',
            );
            ultimoEstado = estado;
            _navegandoAResumen = true;

            // Trigger completion notification

            if (!context.mounted) return;
            debugPrint(
              '[RutaClienteViewModel] Loader cerrado, navegando a ResumenClienteView',
            );
            await navigateWithIntermediateLoader(
              context: context,
              nextBuilder: (_) => ResumenClienteView(solicitudId: solicitudId),
              delay: const Duration(milliseconds: 1400),
              title: 'Viaje finalizado',
              subtitle: 'Preparando tu resumen del viaje...',
            );
            debugPrint('[RutaClienteViewModel] pushReplacement ejecutado');
          } else {
            ultimoEstado = estado;
          }
        });
  }

  String? get conductorId => FirebaseAuth.instance.currentUser?.uid;

  /// Getter para el id del cliente autenticado
  String? get clienteId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> guardarSolicitudActiva(String solicitudId) async {
    await SessionHelper.setActiveSolicitud(solicitudId);
  }

  Future<void> limpiarSolicitudActiva() async {
    await SessionHelper.clearActiveSolicitud();
  }

  Future<bool> restaurarSolicitudActiva(BuildContext context) async {
    final id = await SessionHelper.getActiveSolicitud();
    if (id != null && id.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(id)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final estado = data?['estado'] ?? '';
          if (estado == 'en camino') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RutaClienteDestino(idSolicitud: id),
              ),
            );
            return true;
          }
        }
      } catch (e) {
        debugPrint('Error al verificar estado de solicitud: $e');
      }
    }
    return false;
  }

  @override
  void dispose() {
    // _chatSub?.cancel(); // Chat deshabilitado
    _conductorUbicacionSub?.cancel();
    _solicitudStateSub?.cancel();
    _disposed = true;
    super.dispose();
  }

  Future<void> cargarDatosConductorYUbicacionDestino(String solicitudId) async {
    await guardarSolicitudActiva(solicitudId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;
      final conductor = data['conductor'];
      if (conductor is Map<String, dynamic>) {
        // Nombre
        nombreConductor =
            conductor['nombre'] ??
            conductor['name'] ??
            conductor['displayName'] ??
            '';
        // Foto
        final foto =
            conductor['foto'] ??
            conductor['photo'] ??
            conductor['photoUrl'] ??
            conductor['imagen'] ??
            conductor['avatar'] ??
            conductor['profile_picture'] ??
            '';
        if (foto is String && foto.isNotEmpty) {
          fotoConductor = foto.trim();
        } else if (foto is Map) {
          final url = foto['url'] ?? foto['link'] ?? foto['src'];
          if (url is String && url.isNotEmpty) {
            fotoConductor = url.trim();
          } else {
            fotoConductor = '';
          }
        } else {
          fotoConductor = '';
        }
        // Placa
        placaVehiculo =
            conductor['placa'] ??
            conductor['placaVehiculo'] ??
            conductor['vehiclePlate'] ??
            conductor['placa_auto'] ??
            '';
        // Foto vehículo
        final fotoV =
            conductor['fotoVehiculo'] ??
            conductor['foto_carro'] ??
            conductor['fotoAuto'] ??
            conductor['vehiclePhoto'] ??
            conductor['car_photo'] ??
            '';
        if (fotoV is String && fotoV.isNotEmpty) {
          fotoVehiculo = fotoV.trim();
        } else {
          fotoVehiculo = '';
        }
        // Ubicación del conductor
        final latRaw =
            conductor['lat'] ?? conductor['latitude'] ?? conductor['latitud'];
        latConductor = latRaw != null ? (latRaw as num).toDouble() : null;
        final lngRaw =
            conductor['lng'] ?? conductor['longitude'] ?? conductor['longitud'];
        lngConductor = lngRaw != null ? (lngRaw as num).toDouble() : null;
        debugPrint(
          '[DEBUG] Ubicación conductor: lat=$latConductor, lng=$lngConductor',
        );
      }
      // Buscar lat/lng de destino desde el campo 'destino' (objeto)
      final destino = data['destino'];
      if (destino is Map<String, dynamic>) {
        final lat = destino['lat'] ?? destino['latitude'] ?? destino['latitud'];
        final lng =
            destino['lng'] ?? destino['longitude'] ?? destino['longitud'];
        latDestino = lat != null ? (lat as num).toDouble() : null;
        lngDestino = lng != null ? (lng as num).toDouble() : null;
        if (latDestino != null && lngDestino != null) {
          debugPrint(
            '[DEBUG] Ubicación destino: lat=$latDestino, lng=$lngDestino',
          );
        } else {
          latDestino = null;
          lngDestino = null;
          debugPrint(
            '[DEBUG] Ubicación destino no encontrada en campo destino',
          );
        }
      } else {
        latDestino = null;
        lngDestino = null;
        debugPrint('[DEBUG] Campo destino no encontrado o no es un objeto');
      }
      _safeNotify();
    } catch (e) {
      debugPrint('Error al cargar datos de conductor/cliente: $e');
    }
  }

  void actualizarNombre(String nuevoNombre) {
    nombreConductorEstado = nuevoNombre;
    _safeNotify();
  }

  void actualizarEstado(String nuevoEstado) {
    estado = nuevoEstado;
    _safeNotify();
  }

  void inicializarNotificaciones() {
    _notificaciones.init();
  }

  Future<void> mostrarNotificacion(String titulo, String cuerpo) async {
    try {
      await _notificaciones.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: titulo,
        body: cuerpo,
      );
    } catch (_) {}
  }
}
