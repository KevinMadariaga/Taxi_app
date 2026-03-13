import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaConductorView.dart';
import 'package:taxi_app/widgets/LoaderCompletado.dart';

class Rutaclientedestinoviewmodel extends ChangeNotifier {
          // Tiempo estimado del viaje
          String _tiempoEstimado = '0 min';
          String get tiempoEstimado => _tiempoEstimado;

          // Método para actualizar el tiempo estimado
          void setTiempoEstimado(String tiempo) {
            _tiempoEstimado = tiempo;
            notifyListeners();
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

  // Notificaciones
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

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
      if (ultimoEstado != estado && estado == 'completado') {
        debugPrint('[RutaClienteViewModel] Cambio detectado a "completado". Navegando a ResumenClienteView...');
        ultimoEstado = estado;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LoaderSolicitudCompletada(),
        );
        // Cargar la clase en segundo plano
        final resumenClienteWidget = ChangeNotifierProvider(
          create: (_) => Rutaclientedestinoviewmodel(),
          child: ResumenClienteView(solicitudId: solicitudId,),
        );
        await Future.delayed(const Duration(seconds: 4));
        Navigator.of(context).pop(); // Cierra el loader
        debugPrint('[RutaClienteViewModel] Loader cerrado, navegando a ResumenClienteView');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => resumenClienteWidget,
          ),
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
                builder: (_) => RutaConductor(idSolicitud: id),
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

  // void iniciarChat(String solicitudId) {
  //   _chatSub?.cancel();
  //   _chatSub = chatService.listenMessages(solicitudId).listen(
  //     (ms) {
  //       if (mensajes.isNotEmpty && ms.length > mensajes.length) {
  //         final nuevoMensaje = ms.last;
  //         // Si el mensaje es del conductor, mostrar notificación
  //         if (nuevoMensaje.senderId != usuarioId) {
  //           mostrarNotificacion(
  //             'Mensaje del conductor',
  //             nuevoMensaje.texto
  //           );
  //         }
  //       }
  //       mensajes = ms;
  //       notifyListeners();
  //     },
  //     onError: (e) {
  //       debugPrint("Error en chat: $e");
  //     },
  //   );
  // }

  // Future<void> enviarMensaje(
  //   String solicitudId,
  //   String senderId,
  //   String texto,
  // ) async {
  //   if (texto.trim().isEmpty) return;
  //   await chatService.sendMessage(
  //     solicitudId: solicitudId,
  //     senderId: senderId,
  //     texto: texto,
  //   );
  // }

  @override
  void dispose() {
    // _chatSub?.cancel(); // Chat deshabilitado
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
        nombreConductor = conductor['nombre'] ?? conductor['name'] ?? conductor['displayName'] ?? '';
        // Foto
        final foto = conductor['foto'] ?? conductor['photo'] ?? conductor['photoUrl'] ?? conductor['imagen'] ?? conductor['avatar'] ?? conductor['profile_picture'] ?? '';
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
        placaVehiculo = conductor['placa'] ?? conductor['placaVehiculo'] ?? conductor['vehiclePlate'] ?? conductor['placa_auto'] ?? '';
        // Foto vehículo
        final fotoV = conductor['fotoVehiculo'] ?? conductor['foto_carro'] ?? conductor['fotoAuto'] ?? conductor['vehiclePhoto'] ?? conductor['car_photo'] ?? '';
        if (fotoV is String && fotoV.isNotEmpty) {
          fotoVehiculo = fotoV.trim();
        } else {
          fotoVehiculo = '';
        }
        // Ubicación del conductor
        final latRaw = conductor['lat'] ?? conductor['latitude'] ?? conductor['latitud'];
        latConductor = latRaw != null ? (latRaw as num).toDouble() : null;
        final lngRaw = conductor['lng'] ?? conductor['longitude'] ?? conductor['longitud'];
        lngConductor = lngRaw != null ? (lngRaw as num).toDouble() : null;
        debugPrint('[DEBUG] Ubicación conductor: lat=$latConductor, lng=$lngConductor');
      }
      // Buscar lat/lng de destino desde el campo 'destino' (objeto)
      final destino = data['destino'];
      if (destino is Map<String, dynamic>) {
        final lat = destino['lat'] ?? destino['latitude'] ?? destino['latitud'];
        final lng = destino['lng'] ?? destino['longitude'] ?? destino['longitud'];
        latDestino = lat != null ? (lat as num).toDouble() : null;
        lngDestino = lng != null ? (lng as num).toDouble() : null;
        if (latDestino != null && lngDestino != null) {
          debugPrint('[DEBUG] Ubicación destino: lat=$latDestino, lng=$lngDestino');
        } else {
          latDestino = null;
          lngDestino = null;
          debugPrint('[DEBUG] Ubicación destino no encontrada en campo destino');
        }
      } else {
        latDestino = null;
        lngDestino = null;
        debugPrint('[DEBUG] Campo destino no encontrado o no es un objeto');
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
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> mostrarNotificacion(String titulo, String cuerpo) async {
    print('[Notificacion] Titulo: $titulo, Cuerpo: $cuerpo');
    // Canal de chat y descripción comentados, solo notificación genérica
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'notificacion_channel', // 'chat_channel',
      'Notificaciones', // 'Mensajes del chat',
      // channelDescription: 'Notificaciones de mensajes nuevos del cliente',
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
    print('[Notificacion] show() ejecutado');
  }
}



