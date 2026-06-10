import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';

/// Contraoferta individual de un conductor.
class ContraofertaItem {
  final String conductorId;
  final String conductorNombre;
  final String? conductorFoto;
  final String? placa;
  final double valor;
  final DateTime? createdAt;
  final Map<String, dynamic> conductorPayload;
  final double calificacion; // promedio 0-5
  final int totalCalificaciones;

  const ContraofertaItem({
    required this.conductorId,
    required this.conductorNombre,
    this.conductorFoto,
    this.placa,
    required this.valor,
    this.createdAt,
    required this.conductorPayload,
    this.calificacion = 0,
    this.totalCalificaciones = 0,
  });
}

class BuscandoTaxiViewModel extends ChangeNotifier {
  BuscandoTaxiViewModel({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _solicitudSub;
  bool _disposed = false;
  bool _asignadaHandled = false;
  bool _isCancelling = false;
  bool _isUpdatingValor = false;
  bool _isRespondingCounteroffer = false;
  String? _solicitudId;
  double _valorServicioActual = 0;
  String? _tipoVehiculo;

  // Lista de contraofertas activas (una por conductor)
  List<ContraofertaItem> _contraofertas = [];

  // Compat: campos legacy para solicitudes antiguas sin mapa contraofertas
  double? _valorContraofertaPendiente;
  String? _estadoContraoferta;
  String? _counterOfferToken;
  String? _lastNotifiedCounterOfferToken;

  bool get isCancelling => _isCancelling;
  bool get isUpdatingValor => _isUpdatingValor;
  bool get isRespondingCounteroffer => _isRespondingCounteroffer;
  double get valorServicioActual => _valorServicioActual;
  double? get valorContraofertaPendiente => _valorContraofertaPendiente;
  String? get estadoContraoferta => _estadoContraoferta;
  String? get tipoVehiculo => _tipoVehiculo;
  bool get isMotoSolicitud => (_tipoVehiculo ?? '').toLowerCase() == 'moto';
  List<ContraofertaItem> get contraofertas =>
      List.unmodifiable(_contraofertas);
  bool get hasPendingCounteroffer =>
      _contraofertas.isNotEmpty ||
      (_valorContraofertaPendiente != null &&
          _estadoContraoferta == 'pendiente_cliente');
  String? get counterOfferToken => _counterOfferToken;

  void iniciarEscucha({
    required String? solicitudId,
    required Future<void> Function(String solicitudId) onAsignada,
  }) {
    _solicitudId = solicitudId;
    _asignadaHandled = false;

    _solicitudSub?.cancel();
    if (solicitudId == null || solicitudId.isEmpty) return;

    // Persist so a forced-kill + restart can find and auto-cancel this solicitud.
    SessionHelper.setActiveSolicitud(solicitudId).ignore();

    _solicitudSub = _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((snap) async {
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          _hydratarEstadoDesdeSolicitud(data);
          _safeNotify();

          if (_asignadaHandled) return;

          final estado = (data['estado'] ?? data['status'])
              ?.toString()
              .toLowerCase();
          if (estado == 'asignado') {
            await mostrarNotificacionSolicitudEntrante();
            _asignadaHandled = true;
            try {
              await onAsignada(solicitudId);
            } catch (_) {
              _asignadaHandled = false;
            }
          }
        });
  }

  void _hydratarEstadoDesdeSolicitud(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    double? valor;
    if (tarifa is Map<String, dynamic>) {
      valor = _toDouble(tarifa['total']);
    }
    valor ??= _toDouble(data['valorServicioPropuesto']);
    valor ??= _toDouble(data['valor']);
    _valorServicioActual = valor ?? 0;
    _tipoVehiculo = data['tipoVehiculo']?.toString();

    // ── Nuevo: mapa de contraofertas por conductor ──
    final contMap = data['contraofertas'];
    if (contMap is Map) {
      final newList = <ContraofertaItem>[];
      contMap.forEach((key, raw) {
        if (raw is! Map) return;
        final entry = Map<String, dynamic>.from(raw);
        final estado = entry['estado']?.toString() ?? '';
        if (estado != 'pendiente_cliente') return; // solo las activas

        final conductorRaw = entry['conductor'];
        final Map<String, dynamic> conductorData = conductorRaw is Map
            ? Map<String, dynamic>.from(conductorRaw)
            : <String, dynamic>{};

        final conductorId = conductorData['id']?.toString() ??
            entry['conductorId']?.toString() ??
            key.toString();
        final nombre = conductorData['nombre']?.toString() ??
            entry['conductorNombre']?.toString() ??
            'Conductor';
        final foto = conductorData['foto']?.toString() ??
            conductorData['fotoUrl']?.toString();
        final placa = conductorData['placa']?.toString();
        final v = _toDouble(entry['valor']);
        if (v == null) return;

        DateTime? createdAt;
        final stamp = entry['createdAt'];
        if (stamp is Timestamp) createdAt = stamp.toDate();

        final calif = _toDouble(conductorData['calificacionPromedio'] ??
                conductorData['calificacion'] ??
                conductorData['rating']) ??
            0;
        final totalCalif = (conductorData['totalCalificaciones'] ??
                conductorData['totalRatings'] ??
                conductorData['ratingCount']);
        final totalCalifInt = totalCalif is num ? totalCalif.toInt() : 0;

        newList.add(ContraofertaItem(
          conductorId: conductorId,
          conductorNombre: nombre,
          conductorFoto: foto,
          placa: placa,
          valor: v,
          createdAt: createdAt,
          conductorPayload: conductorData,
          calificacion: calif.clamp(0, 5).toDouble(),
          totalCalificaciones: totalCalifInt,
        ));
      });
      // Ordenar por valor ascendente para mostrar la más barata primero
      newList.sort((a, b) => a.valor.compareTo(b.valor));

      final prevCount = _contraofertas.length;
      _contraofertas = newList;

      // Notificación por cada nueva oferta que aparezca
      if (newList.length > prevCount) {
        for (int i = prevCount; i < newList.length; i++) {
          unawaited(_mostrarNotificacionContraoferta(newList[i].valor));
        }
      }
    } else {
      _contraofertas = [];
    }

    // ── Legacy: campo `contraoferta` único (backward compat) ──
    final contraofertaRaw = data['contraoferta'];
    if (_contraofertas.isEmpty && contraofertaRaw is Map<String, dynamic>) {
      _valorContraofertaPendiente = _toDouble(contraofertaRaw['valor']);
      _estadoContraoferta = contraofertaRaw['estado']?.toString();
      final updatedAt = contraofertaRaw['updatedAt'];
      final createdAt = contraofertaRaw['createdAt'];
      final stamp = updatedAt ?? createdAt;
      _counterOfferToken =
          '${_estadoContraoferta ?? ''}_${_valorContraofertaPendiente?.toStringAsFixed(0) ?? ''}_${_timestampToKey(stamp)}';

      if (_estadoContraoferta == 'pendiente_cliente' &&
          _valorContraofertaPendiente != null) {
        if (_counterOfferToken != _lastNotifiedCounterOfferToken) {
          _lastNotifiedCounterOfferToken = _counterOfferToken;
          unawaited(
            _mostrarNotificacionContraoferta(_valorContraofertaPendiente!),
          );
        }
      }
    } else {
      _valorContraofertaPendiente = null;
      _estadoContraoferta = null;
      _counterOfferToken = null;
    }
  }

  String _timestampToKey(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch.toString();
    }
    return value?.toString() ?? '';
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _mostrarNotificacionContraoferta(double valor) async {
    try {
      final valorTxt = valor.round().toString();
      await NotificacionesServicio.instance.showNotification(
        id: 1002,
        title: 'Contraoferta del conductor',
        body: 'Te proponen un nuevo valor: \$$valorTxt',
      );
    } catch (_) {}
  }

  Future<bool> actualizarValorServicio(double nuevoValor) async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_isUpdatingValor) return false;

    _isUpdatingValor = true;
    _safeNotify();
    try {
      await _firestore.collection('solicitudes').doc(solicitudId).set({
        'valorServicioPropuesto': nuevoValor,
        'estado': 'buscando',
        'estadoContraoferta': 'sin_contraoferta',
        'updatedAt': FieldValue.serverTimestamp(),
        'tarifa': {
          'total': nuevoValor,
          'propuestaCliente': nuevoValor,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'contraoferta': {
          'estado': 'sin_contraoferta',
          'valor': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'contraofertas': FieldValue.delete(),
      }, SetOptions(merge: true));
      _valorServicioActual = nuevoValor;
      _valorContraofertaPendiente = null;
      _estadoContraoferta = 'sin_contraoferta';
      _counterOfferToken = null;
      _contraofertas = [];
      return true;
    } catch (_) {
      return false;
    } finally {
      _isUpdatingValor = false;
      _safeNotify();
    }
  }

  /// Acepta la oferta de un conductor específico.
  Future<bool> aceptarContraofertaDeConductor(String conductorId) async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_isRespondingCounteroffer) return false;

    final oferta = _contraofertas.firstWhere(
      (o) => o.conductorId == conductorId,
      orElse: () => throw StateError('Oferta no encontrada'),
    );

    _isRespondingCounteroffer = true;
    _safeNotify();

    try {
      final ref = _firestore.collection('solicitudes').doc(solicitudId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Solicitud no existe');
        final data = snap.data() ?? <String, dynamic>{};
        final estado = (data['estado'] ?? data['status'])
            ?.toString()
            .toLowerCase();
        if (estado == 'asignado' || estado == 'cancelado') {
          throw StateError('La solicitud ya no está disponible');
        }

        tx.set(ref, {
          'estado': 'asignado',
          'conductor': oferta.conductorPayload,
          'valorServicioPropuesto': oferta.valor,
          'estadoContraoferta': 'aceptada_cliente',
          'updatedAt': FieldValue.serverTimestamp(),
          'fechaAceptacionContraoferta': FieldValue.serverTimestamp(),
          'tarifa': {
            'total': oferta.valor,
            'propuestaCliente': oferta.valor,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'contraoferta': {
            'estado': 'aceptada_cliente',
            'valor': oferta.valor,
            'conductor': oferta.conductorPayload,
            'respondedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          // Limpiar todas las contraofertas pendientes
          'contraofertas': FieldValue.delete(),
        }, SetOptions(merge: true));
      });
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRespondingCounteroffer = false;
      _safeNotify();
    }
  }

  /// Rechaza la oferta de un conductor específico.
  Future<bool> rechazarContraofertaDeConductor(String conductorId) async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_isRespondingCounteroffer) return false;

    _isRespondingCounteroffer = true;
    _safeNotify();

    try {
      await _firestore
          .collection('solicitudes')
          .doc(solicitudId)
          .update({'contraofertas.$conductorId': FieldValue.delete()});
      _contraofertas.removeWhere((o) => o.conductorId == conductorId);
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRespondingCounteroffer = false;
      _safeNotify();
    }
  }

  // ── Legacy compat ──────────────────────────────────────────────────────────

  Future<bool> aceptarContraoferta() async {
    if (_contraofertas.isNotEmpty) {
      return aceptarContraofertaDeConductor(_contraofertas.first.conductorId);
    }
    final solicitudId = _solicitudId;
    final valorContra = _valorContraofertaPendiente;
    if (solicitudId == null || solicitudId.isEmpty || valorContra == null) {
      return false;
    }
    if (_isRespondingCounteroffer) return false;

    _isRespondingCounteroffer = true;
    _safeNotify();

    try {
      final ref = _firestore.collection('solicitudes').doc(solicitudId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Solicitud no existe');

        final data = snap.data() ?? <String, dynamic>{};
        final contraRaw = data['contraoferta'];
        if (contraRaw is! Map<String, dynamic>) {
          throw StateError('No hay contraoferta activa');
        }

        final estado = contraRaw['estado']?.toString();
        final valor = _toDouble(contraRaw['valor']);
        if (estado != 'pendiente_cliente' || valor == null) {
          throw StateError('La contraoferta ya no está disponible');
        }

        final conductorData = contraRaw['conductor'];
        tx.set(ref, {
          'estado': 'asignado',
          'valorServicioPropuesto': valor,
          'estadoContraoferta': 'aceptada_cliente',
          'updatedAt': FieldValue.serverTimestamp(),
          'fechaAceptacionContraoferta': FieldValue.serverTimestamp(),
          'tarifa': {
            'total': valor,
            'propuestaCliente': valor,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'contraoferta': {
            ...contraRaw,
            'estado': 'aceptada_cliente',
            'respondedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'conductor': conductorData,
        }, SetOptions(merge: true));
      });

      return true;
    } catch (_) {
      return false;
    } finally {
      _isRespondingCounteroffer = false;
      _safeNotify();
    }
  }

  Future<bool> rechazarContraoferta() async {
    if (_contraofertas.length == 1) {
      return rechazarContraofertaDeConductor(_contraofertas.first.conductorId);
    }
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_isRespondingCounteroffer) return false;

    _isRespondingCounteroffer = true;
    _safeNotify();

    try {
      await _firestore.collection('solicitudes').doc(solicitudId).set({
        'estado': 'buscando',
        'estadoContraoferta': 'rechazada_cliente',
        'updatedAt': FieldValue.serverTimestamp(),
        'contraoferta': {
          'estado': 'rechazada_cliente',
          'respondedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      _valorContraofertaPendiente = null;
      _estadoContraoferta = 'rechazada_cliente';
      _counterOfferToken = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isRespondingCounteroffer = false;
      _safeNotify();
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

  Future<void> mostrarNotificacionSolicitudEntrante() async {
    try {
      await NotificacionesServicio.instance.showNotification(
        id: 1001,
        title: 'Solicitud asignada',
        body: '¡Un conductor ha sido asignado a tu viaje!',
      );
    } catch (_) {}
  }

  Future<void> detenerEscucha() async {
    final sub = _solicitudSub;
    _solicitudSub = null;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (_) {}
  }

  /// Cancela por inactividad/abandono (app cerrada o en segundo plano demasiado
  /// tiempo). Solo marca estado=cancelado, sin borrar (la app puede no seguir
  /// viva para hacer cleanup). Best-effort.
  Future<void> marcarCanceladaPorInactividad() async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return;
    try {
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'estado': 'cancelado',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': 'inactividad',
      });
    } catch (_) {}
    SessionHelper.clearActiveSolicitud().ignore();
  }

  Future<void> cancelarSolicitud() async {
    if (_isCancelling) return;

    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return;

    _isCancelling = true;
    _safeNotify();

    final docRef = _firestore.collection('solicitudes').doc(solicitudId);
    try {
      await docRef.update({
        'estado': 'cancelado',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[BuscandoTaxiViewModel] update estado cancelado falló: $e');
    }

    try {
      await Future<void>.delayed(const Duration(seconds: 5));
      try {
        await docRef.delete();
        debugPrint(
          '[BuscandoTaxiViewModel] Solicitud $solicitudId eliminada tras cancelación',
        );
      } catch (e) {
        debugPrint(
          '[BuscandoTaxiViewModel] Error eliminando solicitud tras cancelación: $e',
        );
      }
    } catch (e) {
      debugPrint(
        '[BuscandoTaxiViewModel] Error en temporizador de borrado: $e',
      );
    } finally {
      _isCancelling = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _solicitudSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Stream<Map<String, LatLng>> streamConductoresDisponibles() {
    return _firestore
        .collection('usuarios')
        .where('tipoUsuario', isEqualTo: 'conductor')
        .where('disponible', isEqualTo: true)
        .snapshots()
        .map((snap) {
          final positions = <String, LatLng>{};
          for (final doc in snap.docs) {
            final ubicacion = doc.data()['ubicacion'];
            if (ubicacion is! Map) continue;
            final lat = ubicacion['lat'] ?? ubicacion['latitude'];
            final lng = ubicacion['lng'] ?? ubicacion['longitude'];
            if (lat == null || lng == null) continue;
            positions[doc.id] = LatLng(
              (lat as num).toDouble(),
              (lng as num).toDouble(),
            );
          }
          return positions;
        });
  }

  Stream<Map<String, LatLng>> streamConductoresConectados() {
    return _firestore
        .collection('conductores_conectados')
        .snapshots()
        .map((snap) {
          final positions = <String, LatLng>{};
          for (final doc in snap.docs) {
            final ubicacion = doc.data()['ubicacion'];
            if (ubicacion is! Map) continue;
            final lat = ubicacion['lat'] ?? ubicacion['latitude'];
            final lng = ubicacion['lng'] ?? ubicacion['longitude'];
            if (lat == null || lng == null) continue;
            positions[doc.id] = LatLng(
              (lat as num).toDouble(),
              (lng as num).toDouble(),
            );
          }
          return positions;
        });
  }
}
