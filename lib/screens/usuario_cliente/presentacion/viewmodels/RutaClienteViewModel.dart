import 'package:taxi_app/services/map_service.dart';
import 'package:taxi_app/services/ride_service.dart';
import 'package:taxi_app/data/solicitud_repository.dart';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaConductorView.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/tracking_service.dart';

class Rutaclienteviewmodel extends ChangeNotifier {
  // Servicio de mapas
  final MapService _mapService = const MapService();

  /// Obtiene la polyline entre cliente y conductor usando la API de direcciones.
  /// Si la API falla, retorna una línea recta entre ambos.
  Future<List<LatLng>> obtenerPolylineClienteConductor() async {
    if (latCliente == null ||
        lngCliente == null ||
        latConductor == null ||
        lngConductor == null) {
      return [];
    }
    final origen = LatLng(latConductor!, lngConductor!);
    final destino = LatLng(latCliente!, lngCliente!);
    return await _mapService.getRoutePolyline(origen, destino);
  }

  /// Calcula la distancia total de la polyline (en metros).
  double calcularDistanciaPolyline(List<LatLng> polyline) {
    return _mapService.calcularDistanciaPolyline(polyline);
  }

  /// Calcula el tiempo estimado (en segundos) entre conductor y cliente usando la API.
  Future<int?> calcularTiempoEstimado() async {
    if (latCliente == null ||
        lngCliente == null ||
        latConductor == null ||
        lngConductor == null) {
      return -1;
    }
    final origen = LatLng(latConductor!, lngConductor!);
    final destino = LatLng(latCliente!, lngCliente!);
    try {
      final tiempo = await _mapService.calcularTiempoEstimado(origen, destino);
      if (tiempo == null) {
        return -1;
      }
      return tiempo;
    } catch (e) {
      return -1;
    }
  }

  /// Devuelve un stream en tiempo real del estado de la solicitud
  Stream<String?> escucharEstadoSolicitudStream(String solicitudId) {
    return _solicitudRepository.estadoSolicitudStream(solicitudId);
  }

  final RideService _rideService = RideService();
  final SolicitudRepository _solicitudRepository = SolicitudRepository();

  /// Id del usuario actual (cliente)
  String? get usuarioId => FirebaseAuth.instance.currentUser?.uid;

  /// Mensajes no leídos por el usuario actual
  int get mensajesPendientes {
    if (usuarioId == null || mensajes.isEmpty) return 0;
    return mensajes
        .where(
          (m) => !(m.readBy[usuarioId] ?? false) && m.senderId != usuarioId,
        )
        .length;
  }

  // Polyline management
  List<LatLng> polylinePoints = [];
  int indiceActual = 0;

  // Estado de solicitud
  StreamSubscription<DocumentSnapshot>? _solicitudStateSub;
  StreamSubscription<Map<String, dynamic>?>? _conductorUbicacionSub;
  bool _cancelHandled = false;

  /// Escucha en tiempo real la ubicación del conductor y actualiza el ViewModel
  void escucharUbicacionConductor(String solicitudId) {
    _conductorUbicacionSub?.cancel();
    _conductorUbicacionSub = _solicitudRepository
        .conductorUbicacionStream(solicitudId)
        .listen((ubicacion) {
          if (ubicacion != null) {
            latConductor = (ubicacion['lat'] as num?)?.toDouble();
            lngConductor = (ubicacion['lng'] as num?)?.toDouble();
            notifyListeners();
          }
        });
  }

  // Chat
  final ChatService chatService = ChatService();
  StreamSubscription<List<ChatMessage>>? _chatSub;
  bool _chatBootstrapped = false;
  List<ChatMessage> mensajes = [];

  // Datos del conductor y cliente
  String nombreConductor = '';
  String fotoConductor = '';
  String placaVehiculo = '';
  String fotoVehiculo = '';
  double? latCliente;
  double? lngCliente;
  double? latConductor;
  double? lngConductor;

  // Estado del conductor
  String nombreConductorEstado = 'Conductor';
  String estado = 'Disponible';

  // Notificaciones
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Inicia tracking GPS y guarda la ubicación del conductor en Firestore mientras se mueve.
  Future<void> iniciarTrackingUbicacion(String solicitudId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint(
        '[ViewModel] UID de conductor no disponible, abortando tracking.',
      );
      return;
    }
    final trackingService = TrackingService();
    await trackingService.iniciarTrackingConEnvio(
      userId: uid,
      userType: 'conductor',
      solicitudId: solicitudId,
      distanceFilter: 10,
      timeInterval: 10,
    );
    debugPrint('[ViewModel] Tracking de ubicación iniciado.');
  }

  /// Detecta si es la primera vez que se ingresa a la clase con el idSolicitud
  Future<bool> esPrimeraVezClase(String solicitudId) async {
    final activa = await SessionHelper.getActiveSolicitud();
    return activa == null || activa != solicitudId;
  }

  /// Cancela la solicitud cambiando el estado a 'cancelado'.
  Future<void> cancelarSolicitud(String solicitudId) async {
    if (_cancelHandled) return;
    _cancelHandled = true;
    try {
      await _rideService.cancelarSolicitud(solicitudId);
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .update({'cancelledAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('Error al cancelar la solicitud: $e');
      _cancelHandled = false; // Permitir reintento si falla
    }
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
          if (estado == 'asignado') {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => RutaConductor(idSolicitud: id)),
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

  void iniciarChat(String solicitudId) {
    _chatSub?.cancel();
    _chatBootstrapped = false;
    _chatSub = chatService
        .listenMessages(solicitudId)
        .listen(
          (ms) {
            final wasBootstrapped = _chatBootstrapped;
            _chatBootstrapped = true;
            // Evita notificar por mensajes históricos al abrir el chat por primera vez.
            if (wasBootstrapped && ms.length > mensajes.length) {
              final nuevoMensaje = ms.last;
              // Si el mensaje es del conductor, mostrar notificación
              if (nuevoMensaje.senderId != usuarioId) {
                mostrarNotificacion(
                  'Mensaje del conductor',
                  nuevoMensaje.texto,
                );
              }
            }
            mensajes = ms;
            notifyListeners();
          },
          onError: (e) {
            debugPrint("Error en chat: $e");
          },
        );
  }

  Future<void> enviarMensaje(
    String solicitudId,
    String senderId,
    String texto,
  ) async {
    if (texto.trim().isEmpty) return;
    await chatService.sendMessage(
      solicitudId: solicitudId,
      senderId: senderId,
      texto: texto,
    );
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _solicitudStateSub?.cancel();
    _conductorUbicacionSub?.cancel();
    super.dispose();
  }

  Future<void> cargarDatosConductorYUbicacionCliente(String solicitudId) async {
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
        nombreConductor = conductor['nombre'] ?? '';
        final foto =
            conductor['foto'] ??
            conductor['photo'] ??
            conductor['photoUrl'] ??
            conductor['imagen'];
        if (foto is String && foto.isNotEmpty) {
          fotoConductor = foto.trim();
        } else if (foto is Map) {
          final url = foto['url'] ?? foto['link'];
          if (url is String && url.isNotEmpty) {
            fotoConductor = url.trim();
          } else {
            fotoConductor = '';
          }
        } else {
          fotoConductor = '';
        }
        placaVehiculo = conductor['placa'] ?? conductor['placaVehiculo'] ?? '';
        final fotoV =
            conductor['fotoVehiculo'] ??
            conductor['foto_carro'] ??
            conductor['fotoAuto'] ??
            '';
        if (fotoV is String && fotoV.isNotEmpty) {
          fotoVehiculo = fotoV.trim();
        } else {
          fotoVehiculo = '';
        }
        // Ubicación del conductor (lat/lng directamente en el campo conductor)
        latConductor = conductor['lat'] != null
            ? (conductor['lat'] as num).toDouble()
            : null;
        lngConductor = conductor['lng'] != null
            ? (conductor['lng'] as num).toDouble()
            : null;
        debugPrint(
          '[DEBUG] Ubicación conductor: lat=$latConductor, lng=$lngConductor',
        );
      }
      final cliente = data['cliente'];
      if (cliente is Map<String, dynamic>) {
        if (cliente['ubicacion'] is Map<String, dynamic>) {
          final ubicacion = cliente['ubicacion'];
          latCliente = ubicacion['lat'] != null
              ? (ubicacion['lat'] as num).toDouble()
              : null;
          lngCliente = ubicacion['lng'] != null
              ? (ubicacion['lng'] as num).toDouble()
              : null;
          debugPrint(
            '[DEBUG] Ubicación cliente: lat=$latCliente, lng=$lngCliente',
          );
        } else {
          latCliente = null;
          lngCliente = null;
          debugPrint('[DEBUG] Ubicación cliente no encontrada');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error al cargar datos de conductor/cliente: $e');
    }
  }

  void actualizarNombre(String nuevoNombre) {
    nombreConductorEstado = nuevoNombre;
    notifyListeners();
  }

  void actualizarEstado(String nuevoEstado) {
    estado = nuevoEstado;
    notifyListeners();
  }

  void inicializarNotificaciones() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> mostrarNotificacion(String titulo, String cuerpo) async {
    debugPrint('[Notificacion] Titulo: $titulo, Cuerpo: $cuerpo');
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'chat_channel',
          'Mensajes del chat',
          channelDescription: 'Notificaciones de mensajes nuevos del cliente',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );
    await flutterLocalNotificationsPlugin.show(
      0,
      titulo,
      cuerpo,
      platformChannelSpecifics,
    );
    debugPrint('[Notificacion] show() ejecutado');
  }
}
