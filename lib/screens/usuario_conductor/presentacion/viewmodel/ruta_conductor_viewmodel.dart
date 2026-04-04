import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/services/firebase_service.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
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
  bool _cancelHandled = false;
  bool _enCaminoNotificado = false;

  RutaConductorUsuarioViewModel({
    required this.solicitudId,
    this.onSolicitudCancelada,
    NotificacionesServicio? notificacionesServicio,
    FirebaseService? firebaseService,
    TrackingService? trackingService,
  }) : _notificacionesServicio =
           notificacionesServicio ?? NotificacionesServicio.instance,
       _firebaseService = firebaseService ?? FirebaseService(),
       _trackingService = trackingService ?? TrackingService();

  /// Inicializa notificaciones y comienza a escuchar cambios en la solicitud.
  Future<void> init(BuildContext context) async {
    debugPrint('[ViewModel] Inicializando notificaciones...');
    await _notificacionesServicio.init();

    try {
      debugPrint('[ViewModel] Obteniendo solicitud activa de sesión...');
      final activeId = await SessionHelper.getActiveSolicitud();

      debugPrint(
        '[ViewModel] Consultando estado actual de la solicitud en Firestore...',
      );
      String? estadoLower;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(solicitudId)
            .get();
        final data = snap.data();
        if (data != null && data['estado'] != null) {
          estadoLower = data['estado'].toString().toLowerCase();
          debugPrint('[ViewModel] Estado actual de la solicitud: $estadoLower');
        }
        // Log de datos del cliente
        if (data != null && data['cliente'] != null) {
          debugPrint(
            '[ViewModel] Datos del cliente obtenidos: ${data['cliente']}',
          );
        }
      } catch (e) {
        debugPrint('[ViewModel] Error consultando estado: $e');
      }

      final bool esEnCamino =
          estadoLower == 'en camino' ||
          estadoLower == 'on_route' ||
          estadoLower == 'en_ruta';

      if (activeId != null && activeId == solicitudId) {
        debugPrint('[ViewModel] Reanudación de solicitud activa.');
        await _notificacionesServicio.showTripNotification(
          title: 'Solicitud activa',
          body: 'Continúa el servicio',
        );
      } else if (activeId == null && esEnCamino) {
        debugPrint(
          '[ViewModel] Estado es "en camino", marcando como activa en sesión.',
        );
        try {
          await SessionHelper.setActiveSolicitud(solicitudId);
        } catch (e) {
          debugPrint('[ViewModel] Error marcando solicitud activa: $e');
        }
        await _notificacionesServicio.showTripNotification(
          title: 'Solicitud activa',
          body: 'Continúa el servicio',
        );
      } else {
        debugPrint(
          '[ViewModel] Primera vez que se asigna el cliente para esta solicitud.',
        );
        await _notificacionesServicio.showNotification(
          title: 'Cliente asignado',
          body: 'Viaja a recogerlo.',
        );
      }
    } catch (e) {
      debugPrint('[ViewModel] Error en init: $e');
    }

    debugPrint('[ViewModel] Iniciando tracking de ubicación...');
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
            final lat =
                (rawConductor['lat'] ??
                rawConductor['latitude'] ??
                rawConductor['latitud']);
            final lng =
                (rawConductor['lng'] ??
                rawConductor['longitude'] ??
                rawConductor['longitud']);
            if (lat != null && lng != null) {
              debugPrint(
                '[ViewModel] Posición del conductor actualizada: $lat, $lng',
              );
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
    debugPrint('[ViewModel] Nuevo mensaje de chat recibido: $body');
    await _notificacionesServicio.showNotification(
      title: 'Cliente',
      body: body,
    );
  }

  void _listenSolicitudChanges() {
    _solicitudSub?.cancel();
    _solicitudSub = _firebaseService.escucharEstadoViaje(solicitudId).listen((
      estado,
    ) {
      try {
        if (estado == null) return;
        final estadoLower = estado.toLowerCase();
        debugPrint(
          '[ViewModel] Estado de la solicitud actualizado: $estadoLower',
        );

        // Persistir la solicitud activa como en la ruta del cliente
        try {
          // Marcar como activa en estados intermedios de viaje
          if (estadoLower == 'asignado' ||
              estadoLower == 'assigned' ||
              estadoLower == 'en camino' ||
              estadoLower == 'on_route' ||
              estadoLower == 'en_ruta') {
            debugPrint(
              '[ViewModel] Marcando solicitud como activa en sesión...',
            );
            SessionHelper.setActiveSolicitud(solicitudId);
            // Persistir en cache mínimo para restaurar UI
            try {
              // intentar leer datos mínimos del documento
              FirebaseFirestore.instance
                  .collection('solicitudes')
                  .doc(solicitudId)
                  .get()
                  .then((snap) async {
                    final data = snap.data();
                    if (data != null) {
                      final rawCliente = data['cliente'];
                      String? clientName;
                      String? clientAddress;
                      double? clientLat;
                      double? clientLng;
                      if (rawCliente is Map) {
                        clientName =
                            (rawCliente['nombre'] ?? rawCliente['name'])
                                ?.toString();
                        final ubic =
                            rawCliente['ubicacion'] ?? rawCliente['location'];
                        if (ubic is Map) {
                          clientLat =
                              (ubic['lat'] ??
                                      ubic['latitude'] ??
                                      ubic['latitud'])
                                  is num
                              ? (ubic['lat'] ??
                                        ubic['latitude'] ??
                                        ubic['latitud'])
                                    .toDouble()
                              : null;
                          clientLng =
                              (ubic['lng'] ??
                                      ubic['longitude'] ??
                                      ubic['longitud'])
                                  is num
                              ? (ubic['lng'] ??
                                        ubic['longitude'] ??
                                        ubic['longitud'])
                                    .toDouble()
                              : null;
                          clientAddress =
                              (ubic['address'] ??
                                      ubic['direccion'] ??
                                      ubic['title'])
                                  ?.toString();
                          debugPrint(
                            '[ViewModel] Cliente: $clientName, Dirección: $clientAddress, Lat: $clientLat, Lng: $clientLng',
                          );
                        }
                      }
                      try {
                        await RouteCacheService.saveForSolicitud(
                          RouteCacheData(
                            solicitudId: solicitudId,
                            role: 'conductor',
                            clientName: clientName,
                            clientAddress: clientAddress,
                            clientLat: clientLat,
                            clientLng: clientLng,
                          ),
                        );
                        debugPrint(
                          '[ViewModel] Cache de ruta guardado para solicitud $solicitudId',
                        );
                      } catch (e) {
                        debugPrint(
                          '[ViewModel] Error guardando cache de ruta: $e',
                        );
                      }
                    }
                  });
            } catch (e) {
              debugPrint('[ViewModel] Error persistiendo cache: $e');
            }
          }

          // Si el estado cambia a "en camino" (o equivalentes) y aún
          // no hemos notificado, mostrar mensaje de continuación del viaje.
          if ((estadoLower == 'en camino' ||
                  estadoLower == 'on_route' ||
                  estadoLower == 'en_ruta') &&
              !_enCaminoNotificado) {
            _enCaminoNotificado = true;
            debugPrint('[ViewModel] Notificando continuación del viaje...');
            try {
              _notificacionesServicio.showTripNotification(
                title: 'Continúa el viaje',
                body: 'Continúa el viaje, lleva el cliente a su destino.',
              );
            } catch (e) {
              debugPrint(
                '[ViewModel] Error notificando continuación del viaje: $e',
              );
            }
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
            debugPrint('[ViewModel] Limpiando solicitud activa y cache...');
            SessionHelper.clearActiveSolicitud();
            try {
              RouteCacheService.clearSolicitud(solicitudId);
              debugPrint(
                '[ViewModel] Cache de ruta limpiado para solicitud $solicitudId',
              );
            } catch (e) {
              debugPrint('[ViewModel] Error limpiando cache: $e');
            }
          }
        } catch (e) {
          debugPrint('[ViewModel] Error en persistencia de estado: $e');
        }

        if (estadoLower == 'cancelado' || estadoLower == 'cancelada') {
          debugPrint(
            '[ViewModel] Solicitud cancelada, ejecutando callback y notificando...',
          );
          // Delegate UI navigation/transition to the view via callback.
          // ViewModels should not operate on BuildContext directly because
          // async listeners may fire when the UI has been disposed.
          if (!_cancelHandled && onSolicitudCancelada != null) {
            _cancelHandled = true;
            try {
              onSolicitudCancelada!();
            } catch (e) {
              debugPrint(
                '[ViewModel] Error ejecutando callback de cancelación: $e',
              );
            }
          }

          // Notificación en barra del sistema
          _notificacionesServicio.showNotification(
            title: 'Solicitud cancelada',
            body: 'El cliente canceló la solicitud.',
          );
        }
      } catch (e) {
        debugPrint('[ViewModel] Error en listener de estado: $e');
      }
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
      debugPrint(
        '[ViewModel] Marcando solicitud $solicitudId como "en camino"...',
      );
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .update({'estado': 'en camino'});
      debugPrint(
        '[ViewModel] Estado actualizado a "en camino" para solicitud $solicitudId',
      );
    } catch (e) {
      debugPrint('[ViewModel] Error marcando "en camino": $e');
    }
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
      await RouteCacheService.saveForSolicitud(
        RouteCacheData(
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
        ),
      );
    } catch (_) {}
  }

  /// Inicia tracking GPS y guarda la ubicación del conductor en Firestore mientras se mueve.
  Future<void> _iniciarTrackingUbicacion() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint(
        '[ViewModel] UID de conductor no disponible, abortando tracking.',
      );
      return;
    }

    debugPrint(
      '[ViewModel] Solicitando permisos de ubicación en segundo plano...',
    );
    await PermissionsHelper.requestBackgroundLocationPermission();

    debugPrint('[ViewModel] Obteniendo ubicación inicial del conductor...');
    final posInicial = await _trackingService.obtenerUbicacionActual();
    if (posInicial != null) {
      try {
        final latLng = LatLng(posInicial.latitude, posInicial.longitude);
        debugPrint(
          '[ViewModel] Ubicación inicial: ${latLng.latitude}, ${latLng.longitude}',
        );
        await _firebaseService.actualizarUbicacionConductorEnSolicitud(
          solicitudId: solicitudId,
          position: latLng,
        );
        debugPrint('[ViewModel] Ubicación inicial guardada en Firestore.');
      } catch (e) {
        debugPrint('[ViewModel] Error guardando ubicación inicial: $e');
      }
    }

    debugPrint('[ViewModel] Iniciando tracking continuo de ubicación...');
    await _trackingService
        .iniciarTrackingConEnvio(
          userId: uid,
          userType: 'conductor',
          solicitudId: solicitudId,
          distanceFilter: 1,
          timeInterval: 10,
        )
        .then((started) {
          _trackingActivo = started;
          debugPrint('[ViewModel] Tracking activo: $started');
        })
        .catchError((e) {
          _trackingActivo = false;
          debugPrint('[ViewModel] Error iniciando tracking: $e');
        });
  }
}
