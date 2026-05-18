import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/helpers/session_helper.dart';
import 'dart:math' as math;
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/core/services/chat_service_adapter.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;

class RutaDestinoViewModel extends ChangeNotifier {
  late final FirebaseService _firebaseService;
  late final TrackingService _trackingService;

  RutaDestinoViewModel({
    FirebaseService? firebaseService,
    TrackingService? trackingService,
  }) : _firebaseService = firebaseService ?? FirebaseService(),
       _trackingService = trackingService ?? TrackingService();

  final adapter.MapService _mapServiceAdapter = const adapter.MapService();
  bool isLoadingRoute = false;
  LatLng? currentDriverLocation;
  List<LatLng> routePoints = [];

  /// Tracking background location for conductor during trip
  Future<void> iniciarTrackingUbicacion(String solicitudId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint(
        '[RutaDestinoViewModel] UID de conductor no disponible, abortando tracking.',
      );
      return;
    }
    debugPrint(
      '[RutaDestinoViewModel] Solicitando permisos de ubicación en segundo plano...',
    );
    // Si tienes un helper de permisos, úsalo aquí
    // await PermissionsHelper.requestBackgroundLocationPermission();

    debugPrint(
      '[RutaDestinoViewModel] Obteniendo ubicación inicial del conductor...',
    );
    final posInicial = await _trackingService.obtenerUbicacionActual();
    if (posInicial != null) {
      try {
        final latLng = LatLng(posInicial.latitude, posInicial.longitude);
        debugPrint(
          '[RutaDestinoViewModel] Ubicación obtenida con GPS: lat=${latLng.latitude}, lng=${latLng.longitude}',
        );
        await _firebaseService.actualizarUbicacionConductorEnSolicitud(
          solicitudId: solicitudId,
          position: latLng,
        );
        debugPrint(
          '[RutaDestinoViewModel] Ubicación guardada en la base de datos: lat=${latLng.latitude}, lng=${latLng.longitude}',
        );
      } catch (e) {
        debugPrint(
          '[RutaDestinoViewModel] Error guardando ubicación inicial: $e',
        );
      }
    }
    // Iniciar servicio en background (solo si no está corriendo)
    await startBackgroundTrackingService();

    debugPrint(
      '[RutaDestinoViewModel] Iniciando tracking continuo de ubicación...',
    );
    await _trackingService
        .iniciarTrackingConEnvio(
          userId: uid,
          userType: 'conductor',
          solicitudId: solicitudId,
          distanceFilter: 10,
          timeInterval: 10,
        )
        .then((started) {
          debugPrint('[RutaDestinoViewModel] Tracking activo: $started');
        })
        .catchError((e) {
          debugPrint('[RutaDestinoViewModel] Error iniciando tracking: $e');
        });
    debugPrint('[RutaDestinoViewModel] Tracking background iniciado.');
  }

  // Polyline management
  int indiceActual = 0;

  Future<void> fetchRoute(LatLng from, LatLng to) async {
    isLoadingRoute = true;
    currentDriverLocation = from;
    notifyListeners();

    try {
      final points = await _mapServiceAdapter.getRoutePolyline(from, to);
      if (points.isNotEmpty) {
        routePoints = points;
      }
    } catch (e) {
      debugPrint('Error fetching route in ViewModel: $e');
    } finally {
      isLoadingRoute = false;
      notifyListeners();
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
    if (currentDriverLocation == null ||
        (latDestino == null || lngDestino == null)) {
      return null;
    }
    final dest = LatLng(latDestino!, lngDestino!);
    final bearing = calculateBearing(currentDriverLocation!, dest);
    return CameraPosition(
      target: currentDriverLocation!,
      bearing: bearing,
      tilt: 0.0,
      zoom: 16.5,
    );
  }

  /// ------------------------------------------------
  /// ESCUCHA DE ESTADO DE SOLICITUD
  /// ------------------------------------------------
  StreamSubscription<DocumentSnapshot>? _solicitudStateSub;
  bool _completionHandled = false;

  void escucharEstadoSolicitud(
    String solicitudId, {
    Future<void> Function()? onSolicitudCompletada,
  }) {
    _solicitudStateSub?.cancel();
    _completionHandled = false;
    _solicitudStateSub = FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((doc) async {
          if (!doc.exists) return;
          final data = doc.data();
          final estado = data?['estado']?.toString().toLowerCase() ?? '';
          if ((estado == 'completado' || estado == 'completada') &&
              !_completionHandled) {
            _completionHandled = true;
            await finalizarSolicitud(solicitudId);
            if (onSolicitudCompletada != null) {
              await onSolicitudCompletada();
            }
          }
        });
  }

  Future<void> verificarUbicacionPersistida(
    String solicitudId,
    LatLng loc,
  ) async {
    if (!kDebugMode) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      final data = doc.data();
      final storedLat = data?['conductor']?['ubicacion']?['lat'];
      final storedLng = data?['conductor']?['ubicacion']?['lng'];
      debugPrint(
        '[VERIFY] Solicitud $solicitudId storedLat=$storedLat storedLng=$storedLng expectedLat=${loc.latitude} expectedLng=${loc.longitude}',
      );
      if (storedLat == null || storedLng == null) {
        debugPrint('[VERIFY][ERROR] ubicacion no encontrada en documento');
        return;
      }
      final lat = (storedLat as num).toDouble();
      final lng = (storedLng as num).toDouble();
      final latDiff = (lat - loc.latitude).abs();
      final lngDiff = (lng - loc.longitude).abs();
      if (latDiff > 0.0005 || lngDiff > 0.0005) {
        debugPrint(
          '[VERIFY][WARN] Diferencia significativa (latDiff=$latDiff, lngDiff=$lngDiff)',
        );
      } else {
        debugPrint('[VERIFY][OK] Ubicación persistida correctamente');
      }
    } catch (e) {
      debugPrint('[VERIFY][ERROR] Error leyendo doc: $e');
    }
  }

  Future<void> marcarCompletado(String solicitudId) async {
    await FirebaseFirestore.instance.collection('solicitudes').doc(solicitudId).update({
      'estado': 'completado',
      'fecha de terminacion': DateTime.now(),
    });
  }

  Future<void> finalizarSolicitud(String solicitudId) async {
    await limpiarSolicitudActiva();
    try {
      await SessionHelper.clearActiveSolicitud();
    } catch (e) {
      debugPrint('Error clearActiveSolicitud: $e');
    }
    try {
      await RouteCacheService.clearSolicitud(solicitudId);
    } catch (e) {
      debugPrint('Error clearSolicitud: $e');
    }
    final service = FlutterBackgroundService();
    service.invoke("stop");
  }

  /// Getter para el UID del conductor
  String? get conductorId => FirebaseAuth.instance.currentUser?.uid;

  /// ------------------------------------------------
  /// SOLICITUD ACTIVA
  /// ------------------------------------------------

  Future<void> guardarSolicitudActiva(String solicitudId) async {
    await SessionHelper.setActiveSolicitud(solicitudId);
  }

  static Future<String?> obtenerSolicitudActiva() async {
    return await SessionHelper.getActiveSolicitud();
  }

  Future<void> limpiarSolicitudActiva() async {
    await SessionHelper.clearActiveSolicitud();
  }

  static Future<bool> restaurarSolicitudActiva(BuildContext _) async {
    final id = await SessionHelper.getActiveSolicitud();
    if (id != null && id.isNotEmpty) {
      // Consultar Firestore para verificar el estado
      try {
        final doc = await FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(id)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final estado = data?['estado'] ?? '';
          if (estado == 'asignado') {
            return true;
          }
        }
      } catch (e) {
        debugPrint('Error al verificar estado de solicitud: $e');
      }
    }
    return false;
  }

  /// ------------------------------------------------
  /// CHAT
  /// ------------------------------------------------

  final ChatService chatService = ChatService();

  StreamSubscription<List<ChatMessage>>? _chatSub;

  List<ChatMessage> mensajes = [];

  void iniciarChat(String solicitudId) {
    _chatSub?.cancel();
    _chatSub = chatService
        .listenMessages(solicitudId)
        .listen(
          (ms) {
            // Detecta si hay un nuevo mensaje del cliente
            if (mensajes.isNotEmpty && ms.length > mensajes.length) {
              final nuevoMensaje = ms.last;
              if (nuevoMensaje.senderId != conductorId) {
                mostrarNotificacion('Mensaje del cliente', nuevoMensaje.texto);
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
    super.dispose();
  }

  /// ------------------------------------------------
  /// DATOS DEL CLIENTE Y DESTINO
  /// ------------------------------------------------

  String nombreCliente = '';
  String direccionCliente = '';
  String fotoCliente = '';
  double? latCliente;
  double? lngCliente;

  // DESTINO
  double? latDestino;
  double? lngDestino;
  String direccionDestino = '';
  String tituloDestino = '';

  Map<String, dynamic>? _rawCliente;
  Map<String, dynamic>? get rawCliente => _rawCliente;

  Future<void> cargarDatosCliente(String solicitudId) async {
    await guardarSolicitudActiva(solicitudId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;
      final cliente = data['cliente'];
      if (cliente is Map<String, dynamic>) {
        _rawCliente = cliente;

        /// nombre
        nombreCliente = cliente['nombre'] ?? '';

        /// FOTO CLIENTE
        final foto =
            cliente['foto'] ??
            cliente['photo'] ??
            cliente['photoUrl'] ??
            cliente['imagen'];
        if (foto is String && foto.isNotEmpty) {
          fotoCliente = foto.trim();
        } else if (foto is Map) {
          final url = foto['url'] ?? foto['link'];
          if (url is String && url.isNotEmpty) {
            fotoCliente = url.trim();
          } else {
            fotoCliente = '';
          }
        } else {
          fotoCliente = '';
        }

        /// UBICACION CLIENTE
        if (cliente['ubicacion'] is Map<String, dynamic>) {
          final ubicacion = cliente['ubicacion'];
          direccionCliente = ubicacion['address'] ?? '';
          latCliente = ubicacion['lat'] != null
              ? (ubicacion['lat'] as num).toDouble()
              : null;
          lngCliente = ubicacion['lng'] != null
              ? (ubicacion['lng'] as num).toDouble()
              : null;
        } else {
          direccionCliente = '';
          latCliente = null;
          lngCliente = null;
        }
      }
      // Extraer DESTINO de la solicitud
      if (data['destino'] is Map<String, dynamic>) {
        final destino = data['destino'] as Map<String, dynamic>;
        latDestino = destino['lat'] != null
            ? (destino['lat'] as num).toDouble()
            : null;
        lngDestino = destino['lng'] != null
            ? (destino['lng'] as num).toDouble()
            : null;
        direccionDestino = destino['direccion'] ?? '';
        tituloDestino = destino['title'] ?? '';
        print(
          '[RutaDestinoViewModel] Coordenadas destino: lat=$latDestino, lng=$lngDestino',
        );
      } else {
        latDestino = null;
        lngDestino = null;
        direccionDestino = '';
        tituloDestino = '';
        print('[RutaDestinoViewModel] No se encontró destino en la solicitud');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error al cargar datos de cliente/destino: $e');
    }
  }

  /// ------------------------------------------------
  /// ESTADO DEL CONDUCTOR
  /// ------------------------------------------------

  String nombreConductor = 'Conductor';

  String estado = 'Disponible';

  void actualizarNombre(String nuevoNombre) {
    nombreConductor = nuevoNombre;

    notifyListeners();
  }

  void actualizarEstado(String nuevoEstado) {
    estado = nuevoEstado;

    notifyListeners();
  }

  /// ------------------------------------------------
  /// NOTIFICACIONES LOCALES
  /// ------------------------------------------------
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void inicializarNotificaciones() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> mostrarNotificacion(String titulo, String cuerpo) async {
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
  }

  // Inicializa notificaciones en el main o en el initState del ViewModel
  // RutaConductorViewModel.inicializarNotificaciones();
}
