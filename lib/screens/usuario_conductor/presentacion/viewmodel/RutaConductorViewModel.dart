import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';

import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

class RutaConductorViewModel extends ChangeNotifier {
  /// Inicia tracking GPS y guarda la ubicación del conductor en Firestore mientras se mueve.
  Future<void> iniciarTrackingUbicacion(String solicitudId) async {
    // Importa TrackingService y FirebaseService si no están
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint(
        '[ViewModel] UID de conductor no disponible, abortando tracking.',
      );
      return;
    }

    // Solicita permisos de ubicación en segundo plano
    // Si tienes un helper de permisos, úsalo aquí
    // await PermissionsHelper.requestBackgroundLocationPermission();

    // Instancia TrackingService
    final trackingService = TrackingService();

    // Inicia tracking continuo y envía ubicación a Firestore
    await trackingService.iniciarTrackingConEnvio(
      userId: uid,
      userType: 'conductor',
      solicitudId: solicitudId,
      distanceFilter: 1, // 1 metro para pruebas
      timeInterval: 10,
    );
    debugPrint('[ViewModel] Tracking de ubicación iniciado.');
  }

  /// Detecta si es la primera vez que se ingresa a la clase con el idSolicitud
  Future<bool> esPrimeraVezClase(String solicitudId) async {
    final activa = await SessionHelper.getActiveSolicitud();
    // Si no hay solicitud activa o es diferente, es primera vez
    return activa == null || activa != solicitudId;
  }

  // Polyline management
  List<LatLng> polylinePoints = [];
  int indiceActual = 0;

  /// ------------------------------------------------
  /// ESCUCHA DE ESTADO DE SOLICITUD
  /// ------------------------------------------------
  StreamSubscription<DocumentSnapshot>? _solicitudStateSub;
  bool _cancelHandled = false;

  void escucharEstadoSolicitud(String solicitudId, BuildContext context) {
    _solicitudStateSub?.cancel();
    _cancelHandled = false;
    _solicitudStateSub = FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((doc) async {
          if (!doc.exists) return;
          final data = doc.data();
          final estado = data?['estado']?.toString().toLowerCase() ?? '';
          if ((estado == 'cancelado' || estado == 'cancelada') &&
              !_cancelHandled) {
            _cancelHandled = true;
            await limpiarSolicitudActiva();
            try {
              await SessionHelper.clearActiveSolicitud();
            } catch (_) {}
            try {
              await RouteCacheService.clearSolicitud(solicitudId);
            } catch (_) {}
            if (!context.mounted) return;
            await navigateWithIntermediateLoader(
              context: context,
              nextBuilder: (_) => const InicioConductor(),
              delay: const Duration(milliseconds: 1200),
              title: 'Solicitud cancelada',
              subtitle: 'Regresando al inicio...',
              icon: Icons.cancel_rounded,
              clearStackOnNext: true,
            );
          }
        });
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

  static Future<bool> restaurarSolicitudActiva(BuildContext context) async {
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
            if (!context.mounted) return false;
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

  /// ------------------------------------------------
  /// CHAT
  /// ------------------------------------------------

  final ChatService chatService = ChatService();

  StreamSubscription<List<ChatMessage>>? _chatSub;
  bool _chatBootstrapped = false;

  List<ChatMessage> mensajes = [];

  void iniciarChat(String solicitudId) {
    _chatSub?.cancel();
    _chatBootstrapped = false;
    _chatSub = chatService
        .listenMessages(solicitudId)
        .listen(
          (ms) {
            if (_chatBootstrapped) {
              final idsPrevios = mensajes.map((m) => m.id).toSet();
              final nuevosMensajesCliente = ms.where(
                (m) => !idsPrevios.contains(m.id) && m.senderId != conductorId,
              );
              for (final nuevoMensaje in nuevosMensajesCliente) {
                mostrarNotificacion('Mensaje del cliente', nuevoMensaje.texto);
              }
            } else {
              _chatBootstrapped = true;
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
  /// DATOS DEL CLIENTE
  /// ------------------------------------------------

  String nombreCliente = '';

  String direccionCliente = '';

  String fotoCliente = '';

  double? latCliente;

  double? lngCliente;

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

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error al cargar datos de cliente: $e');
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
}
