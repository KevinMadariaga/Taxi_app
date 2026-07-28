import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/data/models/solicitud_item.dart';

/// Lista de solicitudes pendientes visibles para el conductor: binding a
/// Firestore, filtro por distancia (3km) y tipo de vehículo, geocoding de
/// dirección amigable, y el stream de "solicitud nueva" para notificar.
///
/// Extraído de InicioConductorViewmodel (comunidad de menor cohesión del
/// repo según graphify-out/GRAPH_REPORT.md) — es la pieza de mayor riesgo de
/// las 4 identificadas en el diagnóstico: el corazón del home del
/// conductor. El ciclo de vida de la suscripción (cuándo arrancar/parar) NO
/// se movió acá — sigue siendo del vm host, porque ese mismo evento
/// (conectado/desconectado) también limpia el preview (otro controller) y
/// no es responsabilidad de esta lista decidir cuándo el conductor está
/// online.
class PendingSolicitudesController {
  PendingSolicitudesController({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  final List<SolicitudItem> solicitudes = [];
  StreamSubscription<QuerySnapshot>? _sub;
  QuerySnapshot? _lastSolicitudesSnapshot;
  final Set<String> _knownPendingIds = {};
  final Set<String> _resolvingAddressSolicitudIds = {};
  final StreamController<String> _newSolicitudController =
      StreamController<String>.broadcast();
  Stream<String> get onNewSolicitud => _newSolicitudController.stream;

  SolicitudItem? get firstSolicitud =>
      solicitudes.isNotEmpty ? solicitudes.first : null;

  /// Se dispara con cada cambio de estado — el vm host lo usa para su
  /// propio notifyListeners.
  VoidCallback? onChanged;

  /// La ubicación actual y el tipo de vehículo del conductor los posee el vm
  /// host (ubicación y perfil, respectivamente) — se leen vía callback.
  LatLng? Function()? getCurrentLocation;
  String? Function()? getTipoVehiculoConductor;

  void subscribe() {
    _sub?.cancel();
    // Suscribirse solo a solicitudes en estado "pendiente/buscando" para
    // reducir el volumen de datos descargados.
    _sub = _firestore
        .collection('solicitudes')
        .where(
          'estado',
          whereIn: [SolicitudEstado.buscando, 'pending', 'pendiente'],
        )
        .snapshots()
        .listen((snap) {
          _handleQuerySnapshot(snap);
        });
  }

  void stop() {
    _sub?.cancel();
  }

  void clear() {
    solicitudes.clear();
    _knownPendingIds.clear();
  }

  /// Re-filtra localmente el último snapshot cacheado (sin round-trip a
  /// Firestore) — usado cuando cambia `tipoVehiculoConductor` a mitad de
  /// sesión (ver cambiar_vehiculo_view.dart).
  void reprocessLastSnapshot() {
    final cached = _lastSolicitudesSnapshot;
    if (cached != null) {
      _handleQuerySnapshot(cached);
    }
  }

  void _handleQuerySnapshot(QuerySnapshot snap) {
    _lastSolicitudesSnapshot = snap;

    try {
      final currentLocation = getCurrentLocation?.call();
      final currentPendingIds = <String>{};
      final parsedSolicitudes = <SolicitudItem>[];

      for (final doc in snap.docs) {
        final item = _buildPendingSolicitudItem(doc);
        if (item == null) continue;

        if (currentLocation != null) {
          item.distanciaKm = _distanceKm(
            currentLocation.latitude,
            currentLocation.longitude,
            item.ubicacionInicial.latitude,
            item.ubicacionInicial.longitude,
          );

          // Only include solicitudes within 3 km
          if (item.distanciaKm == null || item.distanciaKm! > 3.0) {
            continue;
          }

          // mark as pending for notification comparison (only when within range)
          currentPendingIds.add(doc.id);
        } else {
          // If current location is not yet available, keep solicitudes and show them.
          item.distanciaKm = null;
          currentPendingIds.add(doc.id);
        }

        parsedSolicitudes.add(item);
        unawaited(_completarDatosSolicitud(item));
        unawaited(_ensureFriendlyAddress(item));
      }

      solicitudes
        ..clear()
        ..addAll(parsedSolicitudes);

      try {
        // No se muestra notificación local aquí: la notificación de "nueva
        // solicitud" ya la maneja FCM (ver fcm_service.dart), que la
        // suprime correctamente en foreground (la UI ya la muestra en esta
        // misma lista) y la deja en manos del OS/handler de background para
        // que aparezca una sola vez. Disparar otra aquí duplicaba el aviso
        // y además ignoraba si la app estaba en foreground.
        for (final id in currentPendingIds) {
          if (!_knownPendingIds.contains(id)) {
            try {
              _newSolicitudController.add(id);
            } catch (e, st) {
              ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
            }
          }
        }
        _knownPendingIds
          ..clear()
          ..addAll(currentPendingIds);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
      }

      solicitudes.sort(
        (a, b) => (a.distanciaKm ?? double.maxFinite).compareTo(
          b.distanciaKm ?? double.maxFinite,
        ),
      );
      onChanged?.call();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  SolicitudItem? _buildPendingSolicitudItem(QueryDocumentSnapshot doc) {
    final raw = doc.data();
    if (raw is! Map<String, dynamic>) return null;

    final status = raw['estado'] ?? raw['status'];
    if (!_isPendingStatus(status)) return null;

    final item = SolicitudItem.fromMap(doc.id, raw);
    if (item.clienteId == null || item.clienteId!.isEmpty) return null;

    final lat = item.ubicacionInicial.latitude;
    final lng = item.ubicacionInicial.longitude;
    if (lat == 0 && lng == 0) return null;

    // Filtrar por tipo de vehículo: solo mostrar solicitudes que coincidan
    // con el tipo del conductor. Si el conductor no tiene tipo registrado,
    // muestra todas para compatibilidad con perfiles anteriores.
    final conductorTipo = getTipoVehiculoConductor?.call();
    final solicitudTipo = item.tipoVehiculo?.toLowerCase().trim();
    if (conductorTipo != null &&
        solicitudTipo != null &&
        solicitudTipo.isNotEmpty &&
        conductorTipo != solicitudTipo) {
      return null;
    }

    return item;
  }

  bool _isPendingStatus(dynamic status) {
    if (status == null) return false;
    return SolicitudEstado.normalize(status.toString()) ==
        SolicitudEstado.buscando;
  }

  Future<void> _ensureFriendlyAddress(SolicitudItem item) async {
    final hasAddress =
        (item.origenTitle != null && item.origenTitle!.trim().isNotEmpty) ||
        (item.direccion != null && item.direccion!.trim().isNotEmpty);
    if (hasAddress) return;
    if (!_resolvingAddressSolicitudIds.add(item.id)) return;

    try {
      final placemarks = await placemarkFromCoordinates(
        item.ubicacionInicial.latitude,
        item.ubicacionInicial.longitude,
      );
      if (placemarks.isEmpty) return;

      final p = placemarks.first;
      final parts = [
        p.street?.trim(),
        p.subLocality?.trim(),
        p.locality?.trim(),
      ].whereType<String>().where((value) => value.isNotEmpty);

      final friendly = parts.take(2).join(', ').trim();
      if (friendly.isEmpty) return;

      item.origenTitle = friendly;
      item.direccion = friendly;
      onChanged?.call();
    } catch (_) {
      // Si falla geocoding dejamos fallback a lat/lng en la vista.
    } finally {
      _resolvingAddressSolicitudIds.remove(item.id);
    }
  }

  Future<void> _completarDatosSolicitud(SolicitudItem item) async {
    try {
      if (item.nombreCliente == null) {
        final cli = await _firestore
            .collection('cliente')
            .doc(item.clienteId)
            .get();
        item.nombreCliente = cli.data()?['nombre']?.toString() ?? 'Cliente';
      }
      if (item.direccion == null) {
        item.direccion = 'Ubicación del cliente';
      }
      onChanged?.call();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) =>
      MapHelper.distanceMeters(LatLng(lat1, lon1), LatLng(lat2, lon2)) / 1000;

  void dispose() {
    _sub?.cancel();
    _newSolicitudController.close();
  }
}
