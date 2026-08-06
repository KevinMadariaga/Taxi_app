import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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
  BuscandoTaxiViewModel({
    FirebaseFirestore? firestore,
    adapter.MapService? mapService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _mapService = mapService ?? const adapter.MapService();

  final FirebaseFirestore _firestore;
  final adapter.MapService _mapService;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _solicitudSub;
  bool _disposed = false;
  bool _asignadaHandled = false;
  bool _terminadaHandled = false;
  bool _isCancelling = false;
  bool _isUpdatingValor = false;
  bool _isRespondingCounteroffer = false;
  String? _solicitudId;
  double _valorServicioActual = 0;
  String? _tipoVehiculo;

  // ── Destino + trazado de ruta (búsqueda) ────────────────────────────────
  // Se hidrata desde `data['destino']` (mismo snapshot de la solicitud que ya
  // se escucha en `iniciarEscucha`), y la ruta se calcula una sola vez que se
  // conocen origen (lo aporta la View, vía GPS/caché) y destino.
  LatLng? _destinoLocation;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;

  // Lista de contraofertas activas (una por conductor)
  List<ContraofertaItem> _contraofertas = [];
  // IDs de conductores cuya contraoferta ya fue rechazada: nunca volver a notificar ni mostrar.
  final Set<String> _rejectedContraIds = {};
  // IDs de conductores a quienes ya se les mostró notificación: evita duplicar en snapshots múltiples.
  final Set<String> _notifiedContraIds = {};

  // Compat: campos legacy para solicitudes antiguas sin mapa contraofertas
  double? _valorContraofertaPendiente;
  String? _estadoContraoferta;
  String? _counterOfferToken;
  String? _lastNotifiedCounterOfferToken;

  // ── Tracking de conductores + timers de ciclo de vida ───────────────────────
  // Extraído de BuscandoTaxiView (comunidad de menor cohesión del repo según
  // graphify-out/GRAPH_REPORT.md) — antes vivía en el State del widget: la
  // View suscribía streams del vm ella misma y corría timers de negocio
  // (avisar 5min, cancelar tras 6min en background/2s tras detached) fuera de
  // MVVM. Acá el vm posee la suscripción y el timer completos.
  Map<String, LatLng> conductoresPositions = {};
  Map<String, LatLng> conectadosPositions = {};
  int searchSeconds = 0;
  bool flujoTerminado = false;

  StreamSubscription<Map<String, LatLng>>? _conductoresSub;
  StreamSubscription<Map<String, LatLng>>? _conductoresConectadosSub;
  Timer? _searchTimer;
  Timer? _bgCancelTimer;
  Timer? _detachedCancelTimer;
  bool _notif5minEnviada = false;

  // 6 min en segundo plano sin volver → cancelar solicitud.
  static const Duration _umbralBackgroundCancel = Duration(minutes: 6);
  // 2 s tras destrucción del motor → cancelar solicitud.
  static const Duration _umbralDetachedCancel = Duration(seconds: 2);
  static const int segundosAviso5min = 300;

  bool get isCancelling => _isCancelling;
  bool get isUpdatingValor => _isUpdatingValor;
  bool get isRespondingCounteroffer => _isRespondingCounteroffer;
  double get valorServicioActual => _valorServicioActual;
  double? get valorContraofertaPendiente => _valorContraofertaPendiente;
  String? get estadoContraoferta => _estadoContraoferta;
  String? get tipoVehiculo => _tipoVehiculo;
  bool get isMotoSolicitud => (_tipoVehiculo ?? '').toLowerCase() == 'moto';
  List<ContraofertaItem> get contraofertas => List.unmodifiable(_contraofertas);
  bool get hasPendingCounteroffer =>
      _contraofertas.isNotEmpty ||
      (_valorContraofertaPendiente != null &&
          _estadoContraoferta == 'pendiente_cliente');
  String? get counterOfferToken => _counterOfferToken;
  LatLng? get destinoLocation => _destinoLocation;
  List<LatLng> get routePoints => List.unmodifiable(_routePoints);
  bool get isLoadingRoute => _isLoadingRoute;

  /// [onTerminada] se invoca cuando la solicitud deja de estar buscando por
  /// una vía que NO es la asignación: la canceló un admin, la canceló el
  /// barrido server-side de solicitudes inactivas, expiró a 'sin respuesta',
  /// o el documento desapareció. Sin esto el cliente se queda girando en
  /// "Buscando conductor" para siempre sobre una solicitud que ya no existe
  /// — el único estado que se manejaba era `asignado`.
  void iniciarEscucha({
    required String? solicitudId,
    required Future<void> Function(String solicitudId) onAsignada,
    Future<void> Function(String estadoNormalizado)? onTerminada,
  }) {
    _solicitudId = solicitudId;
    _asignadaHandled = false;
    _terminadaHandled = false;

    _solicitudSub?.cancel();
    if (solicitudId == null || solicitudId.isEmpty) return;

    // Persist so a forced-kill + restart can find and auto-cancel this solicitud.
    SessionHelper.setActiveSolicitud(solicitudId).ignore();

    _solicitudSub = _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((snap) async {
          // Documento borrado: para el cliente equivale a una cancelación.
          if (!snap.exists) {
            await _notificarTerminada(
              SolicitudEstado.cancelado,
              onTerminada,
            );
            return;
          }
          final data = snap.data();
          if (data == null) return;

          _hydratarEstadoDesdeSolicitud(data);
          _safeNotify();

          final estado = SolicitudEstado.normalize(
            (data['estado'] ?? data['status'] ?? '').toString(),
          );

          if (SolicitudEstado.isTerminal(estado)) {
            await _notificarTerminada(estado, onTerminada);
            return;
          }

          if (_asignadaHandled) return;

          if (estado == SolicitudEstado.asignado) {
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

  /// One-shot: si el cliente ya fue enviado al viaje (`_asignadaHandled`) no
  /// tiene sentido sacarlo por un estado terminal posterior (p.ej. el viaje
  /// se completa) — de eso se encarga ya la pantalla de viaje.
  Future<void> _notificarTerminada(
    String estadoNormalizado,
    Future<void> Function(String estadoNormalizado)? onTerminada,
  ) async {
    if (_terminadaHandled || _asignadaHandled) return;
    _terminadaHandled = true;
    if (onTerminada == null) return;
    try {
      await onTerminada(estadoNormalizado);
    } catch (_) {
      _terminadaHandled = false;
    }
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

    final destino = data['destino'];
    if (destino is Map) {
      final lat = destino['lat'];
      final lng = destino['lng'];
      if (lat is num && lng is num) {
        _destinoLocation = LatLng(lat.toDouble(), lng.toDouble());
      }
    }

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

        final conductorId =
            conductorData['id']?.toString() ??
            entry['conductorId']?.toString() ??
            key.toString();
        final nombre =
            conductorData['nombre']?.toString() ??
            entry['conductorNombre']?.toString() ??
            'Conductor';
        final foto =
            conductorData['foto']?.toString() ??
            conductorData['fotoUrl']?.toString();
        final placa = conductorData['placa']?.toString();
        final v = _toDouble(entry['valor']);
        if (v == null) return;

        DateTime? createdAt;
        final stamp = entry['createdAt'];
        if (stamp is Timestamp) createdAt = stamp.toDate();

        final calif =
            _toDouble(
              conductorData['calificacionPromedio'] ??
                  conductorData['calificacion'] ??
                  conductorData['rating'],
            ) ??
            0;
        final totalCalif =
            (conductorData['totalCalificaciones'] ??
            conductorData['totalRatings'] ??
            conductorData['ratingCount']);
        final totalCalifInt = totalCalif is num ? totalCalif.toInt() : 0;

        newList.add(
          ContraofertaItem(
            conductorId: conductorId,
            conductorNombre: nombre,
            conductorFoto: foto,
            placa: placa,
            valor: v,
            createdAt: createdAt,
            conductorPayload: conductorData,
            calificacion: calif.clamp(0, 5).toDouble(),
            totalCalificaciones: totalCalifInt,
          ),
        );
      });
      // Filtrar solo la oferta exacta rechazada (clave conductorId:valor).
      // Si el mismo conductor manda un precio diferente, es oferta nueva → pasa.
      newList.removeWhere(
        (o) => _rejectedContraIds.contains(
          '${o.conductorId}:${o.valor.toStringAsFixed(0)}',
        ),
      );
      // Ordenar por valor ascendente para mostrar la más barata primero
      newList.sort((a, b) => a.valor.compareTo(b.valor));

      _contraofertas = newList;

      // Notificar por cada oferta única (conductorId:valor).
      // El mismo conductor con precio distinto genera nueva notificación.
      for (final item in newList) {
        final key = '${item.conductorId}:${item.valor.toStringAsFixed(0)}';
        if (!_notifiedContraIds.contains(key)) {
          _notifiedContraIds.add(key);
          unawaited(_mostrarNotificacionContraoferta(item.valor));
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

  /// Calcula (una sola vez) la ruta por calle entre [origen] y el destino de
  /// la solicitud, para trazarla en el mapa de búsqueda. Idempotente: llamarla
  /// de nuevo con la ruta ya calculada (o sin destino aún conocido, o
  /// mientras hay una carga en curso) no hace nada — así la View puede
  /// invocarla desde varios puntos (cache/GPS, snapshot de Firestore) sin
  /// duplicar peticiones de red.
  Future<void> calcularRuta(LatLng origen) async {
    final destino = _destinoLocation;
    if (destino == null || _isLoadingRoute || _routePoints.isNotEmpty) return;

    _isLoadingRoute = true;
    _safeNotify();
    try {
      _routePoints = await _mapService.getRoutePolyline(origen, destino);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    } finally {
      _isLoadingRoute = false;
      _safeNotify();
    }
  }

  Future<void> _mostrarNotificacionContraoferta(double valor) async {
    try {
      final valorTxt = _formatMiles(valor.round());
      await NotificacionesServicio.instance.showNotification(
        id: 1002,
        title: 'Contraoferta del conductor',
        body: 'Te proponen un nuevo valor: \$$valorTxt',
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
  }

  static String _formatMiles(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final reverseIndex = s.length - i;
      buf.write(s[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }

  /// Cambia el tipo de vehículo de la solicitud en curso ('carro'/'moto').
  /// No recalcula el valor ofrecido — el cliente lo ajusta por separado,
  /// mismo criterio que ya usa `MapapreviewViewModel` (valor y vehículo son
  /// controles independientes, no atados).
  Future<bool> actualizarTipoVehiculo(String tipo) async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_tipoVehiculo == tipo) return true;
    if (_isUpdatingValor) return false;

    _isUpdatingValor = true;
    _safeNotify();
    try {
      await _firestore.collection('solicitudes').doc(solicitudId).set({
        'tipoVehiculo': tipo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _tipoVehiculo = tipo;
      return true;
    } catch (_) {
      return false;
    } finally {
      _isUpdatingValor = false;
      _safeNotify();
    }
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
        'estado': SolicitudEstado.buscando,
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

    // Solo para validar que la oferta exista localmente antes de abrir la
    // transacción; el valor/payload que realmente se escribe se relee del doc
    // fresco dentro de la transacción (ver abajo), nunca de esta variable.
    _contraofertas.firstWhere(
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
        final estado = SolicitudEstado.normalize(
          (data['estado'] ?? data['status'] ?? '').toString(),
        );
        if (estado == SolicitudEstado.asignado ||
            estado == SolicitudEstado.cancelado) {
          throw StateError('La solicitud ya no está disponible');
        }

        // Revalidar la oferta contra el doc FRESCO leído dentro de la
        // transacción, no contra `_contraofertas` (snapshot local que puede
        // estar desactualizado si el conductor retiró o cambió su oferta justo
        // antes de que el cliente confirmara).
        final contMap = data['contraofertas'];
        final rawEntry = contMap is Map ? contMap[conductorId] : null;
        if (rawEntry is! Map) {
          throw StateError(
            'Esa oferta ya no está disponible, el conductor la retiró.',
          );
        }
        final entry = Map<String, dynamic>.from(rawEntry);
        if (entry['estado']?.toString() != 'pendiente_cliente') {
          throw StateError(
            'Esa oferta ya no está disponible, el conductor la retiró.',
          );
        }
        final valorFresco = _toDouble(entry['valor']);
        if (valorFresco == null) {
          throw StateError('Esa oferta ya no es válida.');
        }
        final conductorPayloadFresco = entry['conductor'] is Map
            ? Map<String, dynamic>.from(entry['conductor'] as Map)
            : <String, dynamic>{'id': conductorId};

        tx.set(ref, {
          'estado': SolicitudEstado.asignado,
          'conductor': conductorPayloadFresco,
          'valorServicioPropuesto': valorFresco,
          'estadoContraoferta': 'aceptada_cliente',
          'updatedAt': FieldValue.serverTimestamp(),
          'fechaAceptacionContraoferta': FieldValue.serverTimestamp(),
          'tarifa': {
            'total': valorFresco,
            'propuestaCliente': valorFresco,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'contraoferta': {
            'estado': 'aceptada_cliente',
            'valor': valorFresco,
            'conductor': conductorPayloadFresco,
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
      // Reject key = conductorId:valor so only THIS specific offer is blocked.
      // A new offer from the same conductor at a different price will show again.
      ContraofertaItem? oferta;
      try {
        oferta = _contraofertas.firstWhere((o) => o.conductorId == conductorId);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
      }
      final rejectKey = oferta != null
          ? '$conductorId:${oferta.valor.toStringAsFixed(0)}'
          : conductorId;
      _rejectedContraIds.add(rejectKey);
      await _firestore.collection('solicitudes').doc(solicitudId).update({
        'contraofertas.$conductorId': FieldValue.delete(),
        // Also update legacy field so the backward-compat path doesn't
        // re-fire a notification when the next snapshot arrives.
        'contraoferta.estado': 'rechazada_cliente',
      });
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
          'estado': SolicitudEstado.asignado,
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
        'estado': SolicitudEstado.buscando,
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
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
  }

  Future<void> detenerEscucha() async {
    final sub = _solicitudSub;
    _solicitudSub = null;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
  }

  /// Cancela por inactividad/abandono (app cerrada o en segundo plano demasiado
  /// tiempo). Marca estado=cancelado y, si la app sigue viva para completar
  /// este método, agenda el borrado a los 3 s (igual que [cancelarSolicitud]),
  /// para que desaparezca de la lista de solicitudes tanto del cliente como
  /// de los conductores. Best-effort.
  Future<void> marcarCanceladaPorInactividad() async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return;
    final docRef = _firestore.collection('solicitudes').doc(solicitudId);
    try {
      await docRef.update({
        'estado': SolicitudEstado.cancelado,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': 'inactividad',
      });
      unawaited(
        _borrarSolicitudTrasGracia(
          docRef,
          solicitudId,
          gracia: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
    SessionHelper.clearActiveSolicitud().ignore();
    SessionHelper.clearActiveSolicitudScreen().ignore();
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
        'estado': SolicitudEstado.cancelado,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[BuscandoTaxiViewModel] update estado cancelado falló: $e');
    } finally {
      _isCancelling = false;
      _safeNotify();
    }
    SessionHelper.clearActiveSolicitud().ignore();
    SessionHelper.clearActiveSolicitudScreen().ignore();

    // Borrado en segundo plano tras una breve gracia (da tiempo a que un
    // conductor que ya estaba enviando su aceptación la complete antes de
    // que el documento desaparezca). No debe bloquear la navegación de
    // vuelta a Home: el cliente ya vio "solicitud cancelada" al instante.
    unawaited(_borrarSolicitudTrasGracia(docRef, solicitudId));
  }

  Future<void> _borrarSolicitudTrasGracia(
    DocumentReference<Map<String, dynamic>> docRef,
    String solicitudId, {
    Duration gracia = const Duration(seconds: 5),
  }) async {
    try {
      await Future<void>.delayed(gracia);
      await docRef.delete();
      debugPrint(
        '[BuscandoTaxiViewModel] Solicitud $solicitudId eliminada tras cancelación',
      );
    } catch (e) {
      debugPrint(
        '[BuscandoTaxiViewModel] Error eliminando solicitud tras cancelación: $e',
      );
    }
  }

  // ── Tracking de conductores ──────────────────────────────────────────────

  void subscribeConductores() {
    _conductoresSub?.cancel();
    _conductoresSub = streamConductoresDisponibles().listen((positions) {
      conductoresPositions = Map<String, LatLng>.from(positions);
      _safeNotify();
    }, onError: (_) {});
  }

  void subscribeConductoresConectados() {
    _conductoresConectadosSub?.cancel();
    _conductoresConectadosSub = streamConductoresConectados().listen((
      positions,
    ) {
      conectadosPositions = Map<String, LatLng>.from(positions);
      _safeNotify();
    }, onError: (_) {});
  }

  // ── Timer de búsqueda ─────────────────────────────────────────────────────

  void startSearchTimer() {
    _searchTimer?.cancel();
    searchSeconds = 0;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      searchSeconds++;
      _safeNotify();
      if (!_notif5minEnviada && searchSeconds >= segundosAviso5min) {
        _notif5minEnviada = true;
        _avisar5Minutos();
      }
    });
  }

  Future<void> _avisar5Minutos() async {
    try {
      await NotificacionesServicio.instance.showNotification(
        id: 1003,
        title: 'Llevas 5 minutos buscando',
        body:
            'Aún no hay conductor. ¿Quieres aumentar tu oferta para '
            'conseguir uno más rápido?',
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
  }

  // ── Ciclo de vida de la app ───────────────────────────────────────────────

  void handleAppLifecycleState(AppLifecycleState state) {
    if (flujoTerminado) return;

    if (state == AppLifecycleState.detached) {
      // Motor Flutter destruido (app cerrada por completo).
      // Esperar 2 s para dar tiempo al SDK a enviar la escritura a Firestore.
      _detachedCancelTimer?.cancel();
      _detachedCancelTimer = Timer(_umbralDetachedCancel, () {
        if (!flujoTerminado) marcarCanceladaPorInactividad();
      });
      return;
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // App en segundo plano: cancelar tras 6 min sin volver.
      _bgCancelTimer?.cancel();
      _bgCancelTimer = Timer(_umbralBackgroundCancel, () {
        if (!flujoTerminado) marcarCanceladaPorInactividad();
      });
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _bgCancelTimer?.cancel();
      _detachedCancelTimer?.cancel();
    }
  }

  /// Marca el flujo como terminado (navegación a viaje asignado, o
  /// cancelación manual) — detiene los timers de background/detached de una
  /// vez. El search timer y la suscripción de conectados se detienen aparte
  /// vía [finalizarTrackingConductores], después del `await` a
  /// `detenerEscucha()` en el caller (mismo orden en dos fases que tenía la
  /// View originalmente).
  void marcarFlujoTerminado() {
    flujoTerminado = true;
    _bgCancelTimer?.cancel();
    _detachedCancelTimer?.cancel();
  }

  /// Segunda fase de limpieza al terminar el flujo.
  ///
  /// Ahora cancela TAMBIÉN `_conductoresSub`. Antes se dejaba viva a propósito
  /// ("mismo comportamiento asimétrico que tenía la View original") y solo la
  /// cerraba `dispose()`, pero como la navegación al viaje se hace con `push`,
  /// `BuscandoTaxiView` sigue montada y esa suscripción quedaba corriendo
  /// durante todo el viaje: una query sin cota sobre `usuarios` que se
  /// re-dispara con cada escritura de cualquier conductor.
  void finalizarTrackingConductores() {
    _searchTimer?.cancel();
    _conductoresConectadosSub?.cancel();
    _conductoresSub?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _solicitudSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
    _bgCancelTimer?.cancel();
    _detachedCancelTimer?.cancel();
    _searchTimer?.cancel();
    _conductoresSub?.cancel();
    _conductoresConectadosSub?.cancel();
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// true si [timestamp] cae dentro del día calendario de hoy (hora local).
  /// Se usa para no mostrar en el mapa a conductores cuya última ubicación
  /// registrada es de ayer o antes (p. ej. quedó "disponible" pero no ha
  /// enviado ubicación hoy) — solo cuentan como "activos ahora" los que
  /// reportaron su posición en el día en curso.
  bool _isFromToday(Timestamp? timestamp) {
    if (timestamp == null) return false;
    final date = timestamp.toDate();
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
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
            if (!_isFromToday(ubicacion['lastUpdated'] as Timestamp?)) {
              continue;
            }
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
    // La colección nunca borra el doc de un conductor al desconectarse, solo
    // se sobrescribe su updatedAt/ubicacion. Sin este filtro server-side el
    // listener descarga TODOS los conductores que alguna vez se conectaron
    // (crece sin límite). Se acota a "hoy" igual que ya hacía _isFromToday,
    // pero antes de bajar la data en vez de después.
    final inicioHoy = DateTime.now();
    final desde = Timestamp.fromDate(
      DateTime(inicioHoy.year, inicioHoy.month, inicioHoy.day),
    );
    return _firestore
        .collection('conductores_conectados')
        .where('updatedAt', isGreaterThanOrEqualTo: desde)
        .snapshots()
        .map((snap) {
          final positions = <String, LatLng>{};
          for (final doc in snap.docs) {
            final data = doc.data();
            if (!_isFromToday(data['updatedAt'] as Timestamp?)) continue;
            final ubicacion = data['ubicacion'];
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
