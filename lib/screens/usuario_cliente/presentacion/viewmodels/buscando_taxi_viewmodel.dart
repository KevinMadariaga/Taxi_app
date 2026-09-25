import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/core/constants/estado_contraoferta.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/dominio/validar_valor_servicio.dart'
    as dominio;
import 'package:taxi_app/core/modelos/vehicle_type.dart';

/// Hitos del contador de búsqueda que la vista tiene que atender.
///
/// Es un evento de UN SOLO USO (la vista lo consume con [consumirEvento]) y
/// no un `bool` por modal: con banderas sueltas, dos hitos cercanos se pisan
/// entre sí y quedan colgadas cuando la vista no alcanza a reaccionar.
/// Agregar un hito futuro es un valor más de este enum, no otra bandera.
enum EventoBusqueda {
  /// Toca proponerle al cliente cambiar el valor de la oferta.
  proponerCambioOferta,

  /// El cliente dejó la propuesta sin responder: la búsqueda se cancela sola.
  canceladaPorInactividad,
}

/// Un conductor conectado, tal como lo ve el cliente en el mapa de búsqueda.
///
/// Trae el tipo de vehículo porque el cliente NO puede resolverlo de
/// `usuarios/{uid}`: las reglas solo lo dejan leer su propio documento. Lo
/// escribe el conductor en su propio doc de `conductores_conectados`.
class ConductorConectado {
  const ConductorConectado({
    required this.ubicacion,
    required this.isMoto,
    required this.visto,
  });

  final LatLng ubicacion;
  final bool isMoto;

  /// `updatedAt` del documento: última señal de vida. Se usa para decidir si
  /// el conductor sigue contando como activo.
  final DateTime visto;
}

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

  /// Último snapshot de `conductores_conectados`, sin filtrar por frescura.
  /// Para dibujar en el mapa usar [conductoresActivos], no esto.
  Map<String, ConductorConectado> conectados = {};

  /// Cuánto vale una señal de vida. El conductor conectado late cada 2 min
  /// (`InicioConductorViewmodel._intervaloRefrescoUbicacion`), así que 5
  /// tolera un latido perdido sin mostrar a alguien que ya se fue.
  static const Duration ventanaConductorActivo = Duration(minutes: 5);

  /// Los que siguen contando como activos AHORA.
  ///
  /// Se filtra al leer y no al recibir el snapshot a propósito: los
  /// snapshots solo llegan cuando alguien escribe, así que si se filtrara
  /// ahí, el último conductor en desconectarse quedaría dibujado para
  /// siempre. La vista se reconstruye cada segundo con el timer de búsqueda,
  /// y en cada reconstrucción esto se vuelve a evaluar.
  List<ConductorConectado> get conductoresActivos {
    final ahora = DateTime.now();
    return conectados.values
        .where((c) => ahora.difference(c.visto) <= ventanaConductorActivo)
        .toList(growable: false);
  }

  int searchSeconds = 0;
  bool flujoTerminado = false;

  StreamSubscription<Map<String, LatLng>>? _conductoresSub;
  StreamSubscription<Map<String, ConductorConectado>>?
  _conductoresConectadosSub;
  Timer? _searchTimer;
  Timer? _bgCancelTimer;
  Timer? _detachedCancelTimer;

  /// Segundo del contador en el que toca volver a proponer el cambio de
  /// oferta. `null` mientras hay una propuesta sin responder.
  int? _segundosProximoModal;

  /// Segundo del contador en el que se levantó la propuesta que sigue sin
  /// responder. `null` si no hay ninguna en el aire.
  int? _esperandoRespuestaDesde;
  EventoBusqueda? _eventoPendiente;

  // 6 min en segundo plano sin volver → cancelar solicitud.
  static const Duration _umbralBackgroundCancel = Duration(minutes: 6);
  // 2 s tras destrucción del motor → cancelar solicitud.
  static const Duration _umbralDetachedCancel = Duration(seconds: 2);

  /// Cada cuánto se le propone al cliente cambiar el valor de la oferta: a
  /// los 5 min de búsqueda, y otra vez 5 min después de cada respuesta suya.
  static const int segundosProponerOferta = 300;

  /// Cuánto se espera una respuesta a esa propuesta antes de cancelar la
  /// solicitud. Lo que cancela es el SILENCIO, no el reloj: mientras el
  /// cliente conteste, la búsqueda sigue viva. Una búsqueda que nadie
  /// atiende, en cambio, le aparece a los conductores como un viaje
  /// disponible que nadie va a tomar.
  static const int segundosSinRespuestaParaCancelar = 300;

  /// Hito del contador pendiente de atender por la vista, o `null`. La vista
  /// lo consume con [consumirEvento] apenas lo lee.
  EventoBusqueda? get eventoPendiente => _eventoPendiente;

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
          _estadoContraoferta == EstadoContraoferta.pendienteCliente);
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
        .listen(
          (snap) async {
            // Documento borrado: para el cliente equivale a una cancelación.
            if (!snap.exists) {
              _notificarTerminada(SolicitudEstado.cancelado, onTerminada);
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
              _notificarTerminada(estado, onTerminada);
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
          },
          onError: (Object e, StackTrace st) {
            // Sin esto, un `permission-denied` o un índice faltante mataba el
            // listener en silencio: ni `onAsignada` ni `onTerminada` volvían a
            // dispararse y el cliente se quedaba girando en "Buscando
            // conductor" para siempre, sin ningún rastro del motivo
            // (auditoría de bugs — mismo patrón ya corregido en
            // `InicioConductorViewModel._subscribeAssignedToMe`).
            ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
          },
        );
  }

  /// One-shot: si el cliente ya fue enviado al viaje (`_asignadaHandled`) no
  /// tiene sentido sacarlo por un estado terminal posterior (p.ej. el viaje
  /// se completa) — de eso se encarga ya la pantalla de viaje.
  void _notificarTerminada(
    String estadoNormalizado,
    Future<void> Function(String estadoNormalizado)? onTerminada,
  ) {
    if (_terminadaHandled || _asignadaHandled) return;
    _terminadaHandled = true;
    if (onTerminada == null) return;
    // One-shot de verdad: el `_terminadaHandled = false` que había en el
    // `catch` re-armaba el handler, así que si la salida fallaba (p.ej. un
    // `Navigator` sobre un context ya desactivado) el próximo snapshot
    // terminal volvía a entrar y disparaba una SEGUNDA navegación con
    // `clearStackOnNext`. Dos de esas dejaban el Navigator con una sola ruta
    // y Flutter cerraba la app.
    //
    // Sin `await` porque no hay nada que hacer después: la View se encarga
    // del resto y este callback es del listener de Firestore.
    unawaited(
      onTerminada(estadoNormalizado).catchError((Object e, StackTrace st) {
        ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
      }),
    );
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
        if (estado != EstadoContraoferta.pendienteCliente)
          return; // solo las activas

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

      // UNA notificación por tanda, no una por oferta. Todas comparten el
      // id 1002, así que en pantalla siempre se vio una sola — pero el bucle
      // disparaba un `show` por oferta nueva y el teléfono sonaba y vibraba
      // N veces seguidas por lo mismo.
      final valoresNuevos = <double>[];
      for (final item in newList) {
        final key = '${item.conductorId}:${item.valor.toStringAsFixed(0)}';
        if (_notifiedContraIds.add(key)) valoresNuevos.add(item.valor);
      }
      if (valoresNuevos.isNotEmpty) {
        unawaited(_mostrarNotificacionContraofertas(valoresNuevos));
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

      if (_estadoContraoferta == EstadoContraoferta.pendienteCliente &&
          _valorContraofertaPendiente != null) {
        if (_counterOfferToken != _lastNotifiedCounterOfferToken) {
          _lastNotifiedCounterOfferToken = _counterOfferToken;
          unawaited(
            _mostrarNotificacionContraofertas([_valorContraofertaPendiente!]),
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

  /// Un solo aviso para todas las contraofertas nuevas de una misma tanda.
  Future<void> _mostrarNotificacionContraofertas(List<double> nuevas) async {
    if (nuevas.isEmpty) return;
    try {
      final menor = nuevas.reduce((a, b) => a < b ? a : b);
      final valorTxt = _formatMiles(menor.round());
      await NotificacionesServicio.instance.showNotification(
        // Misma clave que usa el backend para este evento, así el aviso local
        // y el push no se duplican entre sí.
        id: idNotificacionDe('contraoferta', _solicitudId),
        title: nuevas.length == 1
            ? 'Contraoferta del conductor'
            : '${nuevas.length} contraofertas nuevas',
        body: nuevas.length == 1
            ? 'Te proponen un nuevo valor: \$$valorTxt'
            : 'La más baja: \$$valorTxt',
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

  /// `null` si [digits] es un monto aceptable; si no, el motivo para pintar
  /// en la UI. Misma regla que el sheet de confirmar solicitud — vive en
  /// `dominio/validar_valor_servicio.dart`, no duplicada acá.
  ///
  /// [tipo] explícito para validar contra el vehículo que el cliente está
  /// por elegir en el editor de oferta, que todavía no es el de la solicitud.
  String? validarNuevoValor(String digits, {VehicleType? tipo}) =>
      dominio.validarValorServicio(
        digits,
        tipo: tipo ?? (isMotoSolicitud ? VehicleType.moto : VehicleType.carro),
        distanciaKm: _routePoints.isEmpty
            ? null
            : MapHelper.routeDistanceMeters(_routePoints) / 1000,
        // Sin ruta trazada el techo cae al base×20 (sin el componente por km) y
        // rechazaría el valor que el propio sistema ya aceptó al crear la
        // solicitud. El techo es anti fat-finger, no un recorte retroactivo.
        techoMinimo: _valorServicioActual.round(),
      );

  /// Escribe [cambios] solo si la solicitud sigue en `buscando`.
  ///
  /// Cambiar la oferta o rechazar una contraoferta vuelven a poner
  /// `estado: buscando`. Como `set` plano, si un conductor aceptaba en ese
  /// mismo instante, la escritura del cliente llegaba después y reabría un
  /// viaje ya asignado (con `conductor` puesto): otro conductor podía tomarlo
  /// también y quedaban dos conductores en el mismo viaje.
  Future<void> _setSiSigueBuscando(
    String solicitudId,
    Map<String, dynamic> cambios,
  ) {
    final ref = _firestore.collection('solicitudes').doc(solicitudId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? <String, dynamic>{};
      final estado = SolicitudEstado.normalize(
        (data['estado'] ?? data['status'] ?? '').toString(),
      );
      if (!snap.exists || estado != SolicitudEstado.buscando) {
        throw StateError('La solicitud ya no está disponible');
      }
      tx.set(ref, cambios, SetOptions(merge: true));
    });
  }

  Future<bool> actualizarValorServicio(double nuevoValor) async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return false;
    if (_isUpdatingValor) return false;

    _isUpdatingValor = true;
    _safeNotify();
    try {
      await _setSiSigueBuscando(solicitudId, {
        'valorServicioPropuesto': nuevoValor,
        'estado': SolicitudEstado.buscando,
        'estadoContraoferta': EstadoContraoferta.sinContraoferta,
        'updatedAt': FieldValue.serverTimestamp(),
        'tarifa': {
          'total': nuevoValor,
          'propuestaCliente': nuevoValor,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'contraoferta': {
          'estado': EstadoContraoferta.sinContraoferta,
          'valor': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'contraofertas': FieldValue.delete(),
      });
      _valorServicioActual = nuevoValor;
      _valorContraofertaPendiente = null;
      _estadoContraoferta = EstadoContraoferta.sinContraoferta;
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

    // Antes había acá un `_contraofertas.firstWhere(..., orElse: () => throw
    // StateError(...))` "solo para validar localmente" — pero ese throw
    // quedaba FUERA de este try/catch y el caller tampoco lo capturaba, así
    // que si el conductor retiraba o cambiaba su oferta justo antes de que
    // el cliente confirmara, la excepción escapaba con `_respondingOffer` y
    // `_navegandoAViaje` ya puestos en el caller: spinner permanente, modal
    // irreabrible (auditoría de bugs). Era puramente redundante: la
    // transacción de abajo ya revalida la oferta contra el doc FRESCO y
    // reporta/retorna `false` igual que cualquier otro fallo de esta ruta.
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
        if (entry['estado']?.toString() !=
            EstadoContraoferta.pendienteCliente) {
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
          'estadoContraoferta': EstadoContraoferta.aceptadaCliente,
          'updatedAt': FieldValue.serverTimestamp(),
          'fechaAceptacionContraoferta': FieldValue.serverTimestamp(),
          'tarifa': {
            'total': valorFresco,
            'propuestaCliente': valorFresco,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'contraoferta': {
            'estado': EstadoContraoferta.aceptadaCliente,
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
    } catch (e, st) {
      // Ruta de dinero: aceptar una contraoferta fallaba en silencio, sin
      // rastro en Crashlytics, y el usuario solo veía que el botón no hacía
      // nada.
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
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
      // Transaccional, igual que aceptar. Como `update()` plano, un rechazo
      // podía escribir `contraoferta.estado: 'rechazada_cliente'` DESPUÉS de
      // que la transacción de aceptar hubiera puesto `aceptada_cliente`,
      // dejando el documento ya asignado con la contraoferta marcada como
      // rechazada. Releer el estado dentro de la transacción lo impide.
      final ref = _firestore.collection('solicitudes').doc(solicitudId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw StateError('Solicitud no existe');
        final data = snap.data() ?? <String, dynamic>{};
        final estado = SolicitudEstado.normalize(
          (data['estado'] ?? data['status'] ?? '').toString(),
        );
        // Si ya no está buscando, alguien ganó (o se canceló): no hay nada
        // que rechazar y tocar el documento solo puede corromper el estado.
        if (estado != SolicitudEstado.buscando) {
          throw StateError('La solicitud ya no admite rechazos');
        }
        tx.update(ref, {
          'contraofertas.$conductorId': FieldValue.delete(),
          // Also update legacy field so the backward-compat path doesn't
          // re-fire a notification when the next snapshot arrives.
          'contraoferta.estado': EstadoContraoferta.rechazadaCliente,
        });
      });
      _contraofertas.removeWhere((o) => o.conductorId == conductorId);
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
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
        final estadoSolicitud = SolicitudEstado.normalize(
          (data['estado'] ?? data['status'] ?? '').toString(),
        );
        if (estadoSolicitud != SolicitudEstado.buscando) {
          throw StateError('La solicitud ya no está disponible');
        }
        final contraRaw = data['contraoferta'];
        if (contraRaw is! Map<String, dynamic>) {
          throw StateError('No hay contraoferta activa');
        }

        final estado = contraRaw['estado']?.toString();
        final valor = _toDouble(contraRaw['valor']);
        if (estado != EstadoContraoferta.pendienteCliente || valor == null) {
          throw StateError('La contraoferta ya no está disponible');
        }

        final conductorData = contraRaw['conductor'];
        tx.set(ref, {
          'estado': SolicitudEstado.asignado,
          'valorServicioPropuesto': valor,
          'estadoContraoferta': EstadoContraoferta.aceptadaCliente,
          'updatedAt': FieldValue.serverTimestamp(),
          'fechaAceptacionContraoferta': FieldValue.serverTimestamp(),
          'tarifa': {
            'total': valor,
            'propuestaCliente': valor,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'contraoferta': {
            ...contraRaw,
            'estado': EstadoContraoferta.aceptadaCliente,
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
      await _setSiSigueBuscando(solicitudId, {
        'estado': SolicitudEstado.buscando,
        'estadoContraoferta': EstadoContraoferta.rechazadaCliente,
        'updatedAt': FieldValue.serverTimestamp(),
        'contraoferta': {
          'estado': EstadoContraoferta.rechazadaCliente,
          'respondedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });

      _valorContraofertaPendiente = null;
      _estadoContraoferta = EstadoContraoferta.rechazadaCliente;
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
  /// tiempo). Marca estado=cancelado; con eso desaparece de la lista de
  /// solicitudes tanto del cliente como de los conductores, que filtran por
  /// estado. Best-effort.
  ///
  /// No borra el documento (ver [cancelarSolicitud]): las reglas lo prohíben
  /// y la limpieza real es server-side.
  /// Devuelve el estado que encontró en el servidor: `null` si canceló, o el
  /// estado real si NO canceló porque la solicitud ya había salido de
  /// `buscando`. El caller necesita distinguirlos: si un conductor aceptó un
  /// instante antes, sacar al cliente a la pantalla de inicio con "Búsqueda
  /// cancelada" lo deja fuera de un viaje que sí existe.
  Future<String?> marcarCanceladaPorInactividad() async {
    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return null;
    final docRef = _firestore.collection('solicitudes').doc(solicitudId);
    var cancelo = false;
    String? estadoEncontrado;
    try {
      // Releer el estado FRESCO del servidor dentro de una transacción y
      // cancelar solo si sigue en 'buscando' (mismo defecto de raíz que la
      // carrera de `SolicitudFirestoreDatasource.actualizarEstado`, ver ese
      // comentario): `flujoTerminado` es una bandera LOCAL, así que si el
      // conductor aceptó justo antes de que este timer disparara y el
      // snapshot con 'asignado' todavía no había llegado al teléfono del
      // cliente, este `update` sin condición cancelaba un viaje ya asignado
      // (auditoría de bugs). Si ya no está en 'buscando', no-op silencioso.
      cancelo = await _firestore.runTransaction<bool>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return false;
        final data = snap.data() ?? <String, dynamic>{};
        final estadoServidor = SolicitudEstado.normalize(
          (data['estado'] ?? data['status'] ?? '').toString(),
        );
        if (estadoServidor != SolicitudEstado.buscando) {
          estadoEncontrado = estadoServidor;
          return false;
        }
        tx.set(docRef, {
          'estado': SolicitudEstado.cancelado,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'inactividad',
        }, SetOptions(merge: true));
        return true;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
    SessionHelper.clearActiveSolicitud().ignore();
    SessionHelper.clearActiveSolicitudScreen().ignore();
    // Acá y no en la View: los tres caminos de inactividad (segundo plano,
    // app cerrada, y la propuesta sin responder) pasan por este método, así
    // que el aviso sale una sola vez y desde un solo lugar.
    //
    // Solo si la transacción canceló de verdad: es no-op cuando el conductor
    // aceptó un instante antes, y ahí un push "Búsqueda cancelada" le llega
    // al cliente con el viaje ya asignado.
    if (!cancelo) return estadoEncontrado;
    try {
      await NotificacionesServicio.instance.showNotification(
        id: 1004,
        title: 'Búsqueda cancelada',
        body: 'Cancelamos tu solicitud automáticamente por inactividad.',
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
    }
    return null;
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

    // El documento NO se borra desde el cliente. Antes había un
    // `_borrarSolicitudTrasGracia` que esperaba 5 s y hacía `docRef.delete()`;
    // desde que las reglas están cerradas (`allow delete: if false` en
    // `solicitudes`) esa escritura siempre fallaba con permission-denied y solo
    // dejaba ruido en el log y en Crashlytics — el `estado: cancelado` de
    // arriba ya deja la solicitud terminada a todos los efectos (los lectores
    // filtran por estado).
    //
    // La regla es deliberada: la base de producción no tiene Point-in-Time
    // Recovery, así que un borrado duro es irrecuperable. La limpieza real la
    // hace `cancelarSolicitudesBuscandoInactivas` con el Admin SDK, que no pasa
    // por las reglas.
  }

  // ── Tracking de conductores ──────────────────────────────────────────────

  void subscribeConductores() {
    _conductoresSub?.cancel();
    _conductoresSub = streamConductoresDisponibles().listen(
      (positions) {
        conductoresPositions = Map<String, LatLng>.from(positions);
        _safeNotify();
      },
      onError: (Object e, StackTrace st) {
        // Vacío antes: si `streamConductoresDisponibles` revienta (p.ej. un
        // `lat`/`lng` guardado como String en Firestore, ver el cast sin
        // verificar más abajo), los marcadores de conductores desaparecían
        // del mapa de búsqueda sin ningún rastro (auditoría de bugs).
        ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
      },
    );
  }

  void subscribeConductoresConectados() {
    _conductoresConectadosSub?.cancel();
    _conductoresConectadosSub = streamConductoresConectados().listen(
      (positions) {
        conectados = Map<String, ConductorConectado>.from(positions);
        _safeNotify();
      },
      onError: (Object e, StackTrace st) {
        ErrorReporter.report(e, st, reason: 'buscando_taxi_viewmodel');
      },
    );
  }

  // ── Timer de búsqueda ─────────────────────────────────────────────────────

  void startSearchTimer() {
    _searchTimer?.cancel();
    searchSeconds = 0;
    _segundosProximoModal = segundosProponerOferta;
    _esperandoRespuestaDesde = null;
    _eventoPendiente = null;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      searchSeconds++;
      _evaluarHitos();
      // UNA sola vez y AL FINAL. Notificar antes de evaluar los hitos deja a
      // la vista sin enterarse en el mismo tick que levanta el evento, y el
      // modal no sale hasta el segundo siguiente — o nunca, si para ahí.
      _safeNotify();
    });
  }

  void _evaluarHitos() {
    // El flujo ya terminó (viaje asignado, cancelación manual) pero el search
    // timer sigue vivo hasta `finalizarTrackingConductores()`, que corre
    // después de un `await`. Sin esto, en esa ventana se alcanza a mandar la
    // notificación y a levantar un evento sobre una solicitud ya cerrada.
    if (flujoTerminado) return;

    final esperando = _esperandoRespuestaDesde;
    if (esperando != null) {
      if (searchSeconds - esperando >= segundosSinRespuestaParaCancelar) {
        _esperandoRespuestaDesde = null;
        _eventoPendiente = EventoBusqueda.canceladaPorInactividad;
      }
      // Mientras haya una propuesta en el aire no se agenda otra.
      return;
    }

    final proximo = _segundosProximoModal;
    if (proximo == null) {
      // Ni propuesta en el aire ni próxima agendada: la vista levantó el
      // evento y no pudo mostrar el diálogo (había otro modal encima, la
      // pantalla se estaba desmontando…). Se reagenda en vez de quedar
      // inerte para siempre — y, sobre todo, sin un reloj de cancelación
      // corriendo detrás de un diálogo que el cliente nunca vio.
      _segundosProximoModal = searchSeconds + segundosProponerOferta;
      return;
    }

    if (searchSeconds >= proximo) {
      _segundosProximoModal = null;
      avisarProponerOferta();
      _eventoPendiente = EventoBusqueda.proponerCambioOferta;
    }
  }

  /// La vista confirma que el diálogo quedó EN PANTALLA. Recién ahí arranca
  /// el plazo de silencio.
  ///
  /// Separado de levantar el evento a propósito: si el reloj arrancara al
  /// proponerlo, un evento que la vista no alcanza a mostrar cancelaría la
  /// solicitud sin que al cliente se le haya preguntado nada.
  void registrarPropuestaMostrada() {
    if (flujoTerminado) return;
    _segundosProximoModal = null;
    _esperandoRespuestaDesde = searchSeconds;
  }

  /// La vista marca el evento como atendido apenas lo lee, para que un
  /// rebuild posterior no lo dispare de nuevo.
  void consumirEvento() {
    _eventoPendiente = null;
  }

  /// El cliente contestó la propuesta (cambió la oferta o eligió seguir
  /// buscando): se apaga la cuenta de silencio y se agenda la siguiente a
  /// [segundosProponerOferta] de ahora. Es lo único que evita la cancelación.
  void registrarRespuestaOferta() {
    if (flujoTerminado) return;
    _esperandoRespuestaDesde = null;
    _segundosProximoModal = searchSeconds + segundosProponerOferta;
  }

  /// Notificación local del hito de los 5 min — sirve con la app en segundo
  /// plano, donde el modal no se ve.
  ///
  /// Protegido y visible para tests porque es la costura que el fake
  /// sobreescribe: `NotificacionesServicio` no está mockeado en el entorno de
  /// test y sin esto ningún test puede cruzar los 300 s.
  @protected
  @visibleForTesting
  Future<void> avisarProponerOferta() async {
    try {
      await NotificacionesServicio.instance.showNotification(
        id: 1003,
        title: 'Seguimos buscando conductor',
        body:
            'Aún no hay conductor disponible. ¿Quieres cambiar tu oferta '
            'para conseguir uno más rápido?',
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
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

  Stream<Map<String, ConductorConectado>> streamConductoresConectados() {
    // La colección nunca borra el doc de un conductor al desconectarse, solo
    // se sobrescribe su updatedAt/ubicacion. Sin este filtro server-side el
    // listener descarga TODOS los conductores que alguna vez se conectaron
    // (crece sin límite). Se acota a "hoy" antes de bajar la data.
    //
    // El filtro FINO (5 min) NO va acá: este `desde` se calcula una sola vez,
    // al crear el stream, así que envejecería junto con la pantalla — a la
    // media hora de búsqueda estaría dejando pasar conductores de hace 35
    // minutos. La frescura real se evalúa al leer, en [conductoresActivos].
    final ahora = DateTime.now();
    final desde = Timestamp.fromDate(
      DateTime(ahora.year, ahora.month, ahora.day),
    );
    return _firestore
        .collection('conductores_conectados')
        .where('updatedAt', isGreaterThanOrEqualTo: desde)
        .snapshots()
        .map((snap) {
          final conectados = <String, ConductorConectado>{};
          for (final doc in snap.docs) {
            final data = doc.data();
            final updatedAt = data['updatedAt'] as Timestamp?;
            if (updatedAt == null || !_isFromToday(updatedAt)) continue;
            final ubicacion = data['ubicacion'];
            if (ubicacion is! Map) continue;
            final lat = ubicacion['lat'] ?? ubicacion['latitude'];
            final lng = ubicacion['lng'] ?? ubicacion['longitude'];
            if (lat == null || lng == null) continue;
            conectados[doc.id] = ConductorConectado(
              ubicacion: LatLng(
                (lat as num).toDouble(),
                (lng as num).toDouble(),
              ),
              // Los docs escritos antes de que se guardara el tipo no lo
              // traen: caen a carro, que es el caso mayoritario.
              isMoto:
                  (data['tipoVehiculo']?.toString() ?? '').toLowerCase() ==
                  'moto',
              visto: updatedAt.toDate(),
            );
          }
          return conectados;
        });
  }
}
