import 'dart:async';


import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';


import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaDestinoView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/services/background_tracking_service.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:taxi_app/widgets/LoaderCompletado.dart';


class RutaDestinoViewModel extends ChangeNotifier {
       late final FirebaseService _firebaseService;
       late final TrackingService _trackingService;


       RutaDestinoViewModel({FirebaseService? firebaseService, TrackingService? trackingService})
           : _firebaseService = firebaseService ?? FirebaseService(),
             _trackingService = trackingService ?? TrackingService();


     /// Tracking background location for conductor during trip
     Future<void> iniciarTrackingUbicacion(String solicitudId) async {
   final uid = FirebaseAuth.instance.currentUser?.uid;
   if (uid == null) {
     debugPrint('[RutaDestinoViewModel] UID de conductor no disponible, abortando tracking.');
     return;
   }
   debugPrint('[RutaDestinoViewModel] Solicitando permisos de ubicación en segundo plano...');
   // Si tienes un helper de permisos, úsalo aquí
   // await PermissionsHelper.requestBackgroundLocationPermission();


   debugPrint('[RutaDestinoViewModel] Obteniendo ubicación inicial del conductor...');
   final posInicial = await _trackingService.obtenerUbicacionActual();
   if (posInicial != null) {
     try {
       final latLng = LatLng(posInicial.latitude, posInicial.longitude);
       debugPrint('[RutaDestinoViewModel] Ubicación obtenida con GPS: lat=${latLng.latitude}, lng=${latLng.longitude}');
       await _firebaseService.guardarUbicacionConductor(
         conductorId: uid,
         position: latLng,
       );
       await _firebaseService.actualizarUbicacionConductorEnSolicitud(
         solicitudId: solicitudId,
         position: latLng,
       );
       debugPrint('[RutaDestinoViewModel] Ubicación guardada en la base de datos: lat=${latLng.latitude}, lng=${latLng.longitude}');
     } catch (e) {
       debugPrint('[RutaDestinoViewModel] Error guardando ubicación inicial: $e');
     }
   }
   // Iniciar servicio en background (solo si no está corriendo)
   await startBackgroundTrackingService();


   debugPrint('[RutaDestinoViewModel] Iniciando tracking continuo de ubicación...');
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
     if ((estado == 'completado' || estado == 'completada') && !_cancelHandled) {
       debugPrint('[RutaDestinoViewModel] Estado completado detectado, iniciando navegación a resumen...');
       _cancelHandled = true;
       await limpiarSolicitudActiva();
       try {
         await SessionHelper.clearActiveSolicitud();
       } catch (e) { debugPrint('Error clearActiveSolicitud: $e'); }
       try {
         await RouteCacheService.clearSolicitud(solicitudId);
       } catch (e) { debugPrint('Error clearSolicitud: $e'); }
       // Detener servicio en background
       final service = FlutterBackgroundService();
       service.invoke("stop");
       debugPrint('[RutaDestinoViewModel] Mostrando loader...');
       showDialog(
         context: context,
         barrierDismissible: false,
         builder: (_) => const LoaderSolicitudCompletada(),
       );
       // Cargar la clase en segundo plano
       final resumenConductorWidget = ResumenConductorView(solicitudId: solicitudId);
       await Future.delayed(const Duration(seconds: 2));
       debugPrint('[RutaDestinoViewModel] Cerrando loader y navegando a resumen...');
       if (Navigator.of(context).canPop()) {
         Navigator.of(context).pop(); // Cierra el loader
       }
       Navigator.of(context).pushReplacement(
         MaterialPageRoute(builder: (_) => resumenConductorWidget),
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
         Navigator.of(context).pushReplacement(
           MaterialPageRoute(
             builder: (_) => ChangeNotifierProvider(
               create: (_) => RutaDestinoViewModel(),
               child: RutaDestino(idSolicitud: id),
             ),
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






/// ------------------------------------------------
/// CHAT
/// ------------------------------------------------


final ChatService chatService = ChatService();


StreamSubscription<List<ChatMessage>>? _chatSub;


List<ChatMessage> mensajes = [];


void iniciarChat(String solicitudId) {
 _chatSub?.cancel();
 _chatSub = chatService.listenMessages(solicitudId).listen(
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
     final foto = cliente['foto'] ??
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
     latDestino = destino['lat'] != null ? (destino['lat'] as num).toDouble() : null;
     lngDestino = destino['lng'] != null ? (destino['lng'] as num).toDouble() : null;
     direccionDestino = destino['direccion'] ?? '';
     tituloDestino = destino['title'] ?? '';
     print('[RutaDestinoViewModel] Coordenadas destino: lat=$latDestino, lng=$lngDestino');
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
static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();


static void inicializarNotificaciones() {
 const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
 const InitializationSettings initializationSettings = InitializationSettings(
   android: initializationSettingsAndroid,
 );
 flutterLocalNotificationsPlugin.initialize(initializationSettings);
}


static Future<void> mostrarNotificacion(String titulo, String cuerpo) async {
 const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
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
