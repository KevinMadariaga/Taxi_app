import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';
import 'package:taxi_app/services/firebase_service.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/services/tracking_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';



/// ViewModel ligero para manejar la lógica de negocio de RutaConductorView
/// (notificaciones locales y escucha del estado de la solicitud).
class RutaConductorUsuarioViewModel {
  final String solicitudId;
  final NotificacionesServicio _notificacionesServicio;
  final FirebaseService _firebaseService;
  final TrackingService _trackingService;
  final VoidCallback? onSolicitudCancelada;

  StreamSubscription<String?>? _solicitudSub;
  bool _trackingActivo = false;

  RutaConductorUsuarioViewModel({
    required this.solicitudId,
    this.onSolicitudCancelada,
    NotificacionesServicio? notificacionesServicio,
    FirebaseService? firebaseService,
    TrackingService? trackingService,
  }) : _notificacionesServicio = notificacionesServicio ?? NotificacionesServicio.instance,
       _firebaseService = firebaseService ?? FirebaseService(),
       _trackingService = trackingService ?? TrackingService();

  /// Inicializa notificaciones y comienza a escuchar cambios en la solicitud.
  Future<void> init(BuildContext context) async {
    await _notificacionesServicio.init();

    // Notificación cuando el conductor entra a la ruta
    _notificacionesServicio.showNotification(
      title: 'Cliente asignado',
      body: 'Viaja a recogerlo.',
    );

    await _iniciarTrackingUbicacion();
    // Do not use the provided BuildContext inside async listeners —
    // delegate UI navigation/transition to the optional callback
    _listenSolicitudChanges();
  }

  /// Stream en tiempo real de la posición del conductor tomada desde la solicitud.
  /// Retorna `LatLng` cuando existe `conductor.lat/lng` en el documento de la solicitud.
  Stream<LatLng> listenPosicionConductor() {
    return FirebaseFirestore.instance
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) return null;
          final rawConductor = data['conductor'];
          if (rawConductor is Map) {
            final lat = (rawConductor['lat'] ?? rawConductor['latitude'] ?? rawConductor['latitud']);
            final lng = (rawConductor['lng'] ?? rawConductor['longitude'] ?? rawConductor['longitud']);
            if (lat != null && lng != null) {
              return LatLng((lat as num).toDouble(), (lng as num).toDouble());
            }
          }
          return null;
        })
        .where((pos) => pos != null)
        .cast<LatLng>();
  }

  /// Dispara una notificación cuando llega un nuevo mensaje del cliente.
  Future<void> notifyNewChatMessage(String texto) async {
    final body = texto.trim();
    if (body.isEmpty) return;
    await _notificacionesServicio.showNotification(
      title: 'Nuevo mensaje del cliente',
      body: body,
    );
  }

  void _listenSolicitudChanges() {
    _solicitudSub?.cancel();
    _solicitudSub = _firebaseService
        .escucharEstadoViaje(solicitudId)
        .listen((estado) {
      try {
        if (estado == null) return;
        final estadoLower = estado.toLowerCase();

        // Persistir la solicitud activa como en la ruta del cliente
        try {
          // Marcar como activa en estados intermedios de viaje
          if (estadoLower == 'asignado' ||
              estadoLower == 'assigned' ||
              estadoLower == 'en camino' ||
              estadoLower == 'on_route' ||
              estadoLower == 'en_ruta') {
            SessionHelper.setActiveSolicitud(solicitudId);
            // Persistir en cache mínimo para restaurar UI
            try {
              // intentar leer datos mínimos del documento
              FirebaseFirestore.instance.collection('solicitudes').doc(solicitudId).get().then((snap) async {
                final data = snap.data();
                if (data != null) {
                  final rawCliente = data['cliente'];
                  String? clientName;
                  String? clientAddress;
                  double? clientLat;
                  double? clientLng;
                  if (rawCliente is Map) {
                    clientName = (rawCliente['nombre'] ?? rawCliente['name'])?.toString();
                    final ubic = rawCliente['ubicacion'] ?? rawCliente['location'];
                    if (ubic is Map) {
                      clientLat = (ubic['lat'] ?? ubic['latitude'] ?? ubic['latitud']) is num ? (ubic['lat'] ?? ubic['latitude'] ?? ubic['latitud']).toDouble() : null;
                      clientLng = (ubic['lng'] ?? ubic['longitude'] ?? ubic['longitud']) is num ? (ubic['lng'] ?? ubic['longitude'] ?? ubic['longitud']).toDouble() : null;
                      clientAddress = (ubic['address'] ?? ubic['direccion'] ?? ubic['title'])?.toString();
                    }
                  }
                  try {
                    await RouteCacheService.saveForSolicitud(RouteCacheData(
                      solicitudId: solicitudId,
                      role: 'conductor',
                      clientName: clientName,
                      clientAddress: clientAddress,
                      clientLat: clientLat,
                      clientLng: clientLng,
                    ));
                  } catch (_) {}
                }
              });
            } catch (_) {}
          }

          // Limpiar cuando finaliza o se cancela
          if (estadoLower == 'cancelado' ||
              estadoLower == 'cancelada' ||
              estadoLower == 'finalizado' ||
              estadoLower == 'finalizada' ||
              estadoLower == 'terminado' ||
              estadoLower == 'terminada' ||
              estadoLower == 'completado' ||
              estadoLower == 'completada') {
            SessionHelper.clearActiveSolicitud();
            try { RouteCacheService.clearSolicitud(solicitudId); } catch (_) {}
          }
        } catch (_) {}

        if (estadoLower == 'cancelado' || estadoLower == 'cancelada') {
          // Delegate UI navigation/transition to the view via callback.
          // ViewModels should not operate on BuildContext directly because
          // async listeners may fire when the UI has been disposed.
          if (onSolicitudCancelada != null) {
            try {
              onSolicitudCancelada!();
            } catch (_) {}
          }

          // Notificación en barra del sistema
          _notificacionesServicio.showNotification(
            title: 'Solicitud cancelada',
            body: 'El cliente canceló la solicitud.',
          );
        }
      } catch (_) {}
    });
  }

  void dispose() {
    _solicitudSub?.cancel();
    _solicitudSub = null;
    if (_trackingActivo) {
      _trackingService.detenerTracking();
      _trackingActivo = false;
    }
  }

  /// Marca la solicitud como 'en camino' para indicar que el conductor inició
  /// la ruta hacia el destino/cliente. Se usa desde la vista al pulsar
  /// "Ya llegué" para actualizar el estado en Firestore.
  Future<void> marcarEnCamino() async {
    try {
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .update({'estado': 'en camino'});
    } catch (_) {}
  }

  /// Persist minimal route cache for restoration after app restart.
  Future<void> persistCache({
    String? clientName,
    String? clientAddress,
    double? clientLat,
    double? clientLng,
    String? conductorId,
    String? conductorName,
    String? conductorPhotoUrl,
    String? conductorPlate,
  }) async {
    try {
      await RouteCacheService.saveForSolicitud(RouteCacheData(
        solicitudId: solicitudId,
        role: 'conductor',
        clientName: clientName,
        clientAddress: clientAddress,
        clientLat: clientLat,
        clientLng: clientLng,
        conductorId: conductorId,
        conductorName: conductorName,
        conductorPhotoUrl: conductorPhotoUrl,
        conductorPlate: conductorPlate,
      ));
    } catch (_) {}
  }

  /// Inicia tracking GPS y guarda la ubicación del conductor en Firestore mientras se mueve.
  Future<void> _iniciarTrackingUbicacion() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Asegurar permisos de segundo plano para tracking continuo
    await PermissionsHelper.requestBackgroundLocationPermission();

    // Sembrar ubicación inicial para que Firestore tenga el último punto antes de empezar el stream
    final posInicial = await _trackingService.obtenerUbicacionActual();
    if (posInicial != null) {
      try {
        final latLng = LatLng(posInicial.latitude, posInicial.longitude);
        await _firebaseService.guardarUbicacionConductor(
          conductorId: uid,
          position: latLng,
        );
        await _firebaseService.actualizarUbicacionConductorEnSolicitud(
          solicitudId: solicitudId,
          position: latLng,
        );
      } catch (_) {}
    }

    await _trackingService.iniciarTrackingConEnvio(
      userId: uid,
      userType: 'conductor',
      solicitudId: solicitudId,
      distanceFilter: 8,
      timeInterval: 5,
    ).then((started) {
      _trackingActivo = started;
    }).catchError((_) {
      _trackingActivo = false;
    });
  }
}
