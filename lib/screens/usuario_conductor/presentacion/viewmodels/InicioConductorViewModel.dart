import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/data/models/solicitud_item.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/controllers/preview_route_controller.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/controllers/conductor_profile_controller.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/controllers/pending_solicitudes_controller.dart';
import 'package:taxi_app/core/services/tracking_service.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/core/constants/estado_contraoferta.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

class InicioConductorViewmodel extends ChangeNotifier {
  InicioConductorViewmodel({
    FirebaseFirestore? firestore,
    TrackingService? trackingService,
    FirebaseAuth? auth,
    void Function(String userId)? iniciarEscuchaSoporte,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _trackingService = trackingService ?? TrackingService(),
       _auth = auth ?? FirebaseAuth.instance,
       _iniciarEscuchaSoporte =
           iniciarEscuchaSoporte ??
           SoporteNotificationService.instance.iniciarEscuchaUsuario,
       _previewController = PreviewRouteController(
         firestore: firestore ?? FirebaseFirestore.instance,
         trackingService: trackingService ?? TrackingService(),
       ),
       _profileController = ConductorProfileController(
         firestore: firestore ?? FirebaseFirestore.instance,
         auth: auth ?? FirebaseAuth.instance,
       ),
       _solicitudesController = PendingSolicitudesController(
         firestore: firestore ?? FirebaseFirestore.instance,
       ) {
    _previewController.onChanged = _safeNotify;
    _previewController.getCurrentLocation = () => currentLocation;
    _previewController.onLocationRefreshed = (loc) => currentLocation = loc;
    _profileController.onChanged = _safeNotify;
    // Cada snapshot de la lista re-hidrata la preview abierta: sin esto la
    // tarjeta quedaba congelada con los datos del momento en que se abrió
    // (ver `resyncSelectedPreview`).
    _solicitudesController.onChanged = () {
      _previewController.resyncSelectedPreview(
        _solicitudesController.solicitudes,
      );
      _safeNotify();
    };
    _solicitudesController.getCurrentLocation = () => currentLocation;
    _solicitudesController.getTipoVehiculoConductor = () =>
        _profileController.tipoVehiculoConductor;
    _solicitudesController.getConductorUid = () => _auth.currentUser?.uid;
  }

  /// Preview de solicitud seleccionada + su ruta en el mapa. Ver
  /// `controllers/preview_route_controller.dart`.
  final PreviewRouteController _previewController;

  /// Perfil del conductor (identidad + rating). Ver
  /// `controllers/conductor_profile_controller.dart`.
  final ConductorProfileController _profileController;

  /// Lista de solicitudes pendientes visibles. Ver
  /// `controllers/pending_solicitudes_controller.dart`.
  final PendingSolicitudesController _solicitudesController;

  bool isConnected = false;
  StreamSubscription<DocumentSnapshot>? _conductorSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _previewStatusSub;
  StreamSubscription<QuerySnapshot>? _assignedSub;
  bool _previewStatusHandled = false;
  // Solicitudes ya asignadas a este conductor que ya navegamos (evita repetir).
  final Set<String> _handledAssigned = {};

  /// Se invoca cuando una solicitud queda asignada a ESTE conductor
  /// (acepta él, o el cliente acepta su contraoferta), sin importar si tenía
  /// la preview abierta. La vista la usa para navegar a la ruta.
  void Function(String solicitudId)? onAsignadoAMi;
  final FirebaseFirestore _firestore;
  final TrackingService _trackingService;
  final FirebaseAuth _auth;
  final void Function(String userId) _iniciarEscuchaSoporte;

  bool _disposed = false;
  bool isTogglingConnection = false;

  // ===== Perfil + rating (delegado a ConductorProfileController) =====
  double get rating => _profileController.rating;
  int get totalRatings => _profileController.totalRatings;
  int get totalCompletedTrips => _profileController.totalCompletedTrips;
  double get totalServiceValue => _profileController.totalServiceValue;
  String get displayName => _profileController.displayName;
  String? get photoUrl => _profileController.photoUrl;
  String? get nameFromDb => _profileController.nameFromDb;
  String? get plate => _profileController.plate;
  String? get vehiclePhotoUrl => _profileController.vehiclePhotoUrl;
  String? get tipoVehiculoConductor => _profileController.tipoVehiculoConductor;
  set tipoVehiculoConductor(String? value) =>
      _profileController.tipoVehiculoConductor = value;
  String? get vehiclePlate => _profileController.vehiclePlate;
  String? get vehiclePhoto => _profileController.vehiclePhoto;

  void setDisplayName(String name) => _profileController.setDisplayName(name);

  LatLng? currentLocation;

  // ===== Notifiers dedicados al mapa (aislamiento de rebuilds) =====
  // `InicioConductorView` envuelve casi toda la pantalla (2126 líneas,
  // incluido el GoogleMap) en un único `Consumer<InicioConductorViewmodel>`.
  // Como los 3 sub-controllers (preview, perfil, solicitudes pendientes)
  // delegan TODOS sus cambios al mismo `notifyListeners()`, cualquier cambio
  // ajeno al mapa (ej. rating del perfil, lista de solicitudes) reconstruye
  // también el GoogleMap. Estos `ValueNotifier` exponen solo los datos que
  // el mapa necesita para que la vista pueda aislarlo con un
  // `AnimatedBuilder` (mismo patrón que `_AnimatedConductorMap` en
  // trip_tracking_screen.dart), sin tener que escuchar el VM completo.
  // Se sincronizan en `_syncMapNotifiers()` (llamado desde `_safeNotify()`)
  // con chequeo de igualdad para no emitir un valor nuevo si el contenido
  // no cambió realmente.
  final ValueNotifier<LatLng?> currentLocationNotifier = ValueNotifier<LatLng?>(
    null,
  );
  final ValueNotifier<PreviewSolicitud?> selectedPreviewNotifier =
      ValueNotifier<PreviewSolicitud?>(null);
  final ValueNotifier<Set<Marker>> extraMarkersNotifier =
      ValueNotifier<Set<Marker>>(const <Marker>{});
  final ValueNotifier<Set<Polyline>> routePolylinesNotifier =
      ValueNotifier<Set<Polyline>>(const <Polyline>{});

  bool _unorderedSetEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  void _syncMapNotifiers() {
    if (currentLocationNotifier.value != currentLocation) {
      currentLocationNotifier.value = currentLocation;
    }
    if (!identical(selectedPreviewNotifier.value, selectedPreview)) {
      selectedPreviewNotifier.value = selectedPreview;
    }
    if (!_unorderedSetEquals(extraMarkersNotifier.value, extraMarkers)) {
      extraMarkersNotifier.value = Set<Marker>.of(extraMarkers);
    }
    if (!_unorderedSetEquals(routePolylinesNotifier.value, routePolylines)) {
      routePolylinesNotifier.value = Set<Polyline>.of(routePolylines);
    }
  }

  bool isLoading = true;
  bool loadingLocation = true;

  // ===== Solicitudes pendientes (delegado a PendingSolicitudesController) =====
  List<SolicitudItem> get solicitudes => _solicitudesController.solicitudes;
  Stream<String> get onNewSolicitud => _solicitudesController.onNewSolicitud;
  SolicitudItem? get firstSolicitud => _solicitudesController.firstSolicitud;

  // Método de inicialización principal
  Future<void> init() async {
    isLoading = true;
    loadingLocation = true;
    _safeNotify();
    // Red de seguridad: si el flujo de viaje anterior falló al detener el
    // tracking en background (ver RutaDestinoView/resumen_viaje), no debe
    // seguir corriendo una vez el conductor está de vuelta en el home.
    unawaited(stopBackgroundTrackingService());
    _profileController.listenCachedName();
    // Kick off async startup tasks but do not await them so UI can render fast.
    _profileController.loadProfile();
    // El permiso de background debe pedirse después del foreground: Android
    // 11+ exige "whileInUse" concedido antes de poder solicitar "always".
    // PermissionsHelper._runExclusive serializa por orden de llamada, así
    // que _loadLocation() (que pide foreground) debe encolarse primero.
    _loadLocation();
    _requestBackgroundLocationPermission();

    // Subscriptions can be registered immediately; they will react when data arrives.
    _subscribeConductorStatus();
    ensureSolicitudesSubscription();
    _profileController.subscribeRatings();
    _subscribeAssignedToMe();

    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _iniciarEscuchaSoporte(uid);
    }

    // Mark initial loading as false to avoid blocking UI; specific flags (like loadingLocation)
    // remain true until their respective tasks complete and update the VM.
    isLoading = false;
    _safeNotify();
  }

  Future<void> _loadLocation() async {
    loadingLocation = true;
    _safeNotify();
    try {
      // Obtener ubicación con TrackingService
      final position = await _trackingService.obtenerUbicacionActual();
      if (position != null) {
        currentLocation = LatLng(position.latitude, position.longitude);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    loadingLocation = false;
    _safeNotify();

    // Si ahora ya tenemos ubicación y el conductor está conectado, re-subscribimos
    // para asegurar que la lista de solicitudes se reevalúe con la distancia correcta.
    if (currentLocation != null && isConnected) {
      ensureSolicitudesSubscription();
      // La resubscripción reconstruye SolicitudItem nuevos, pero si ya había
      // una preview abierta (referencia al item viejo, con distanciaKm null
      // por falta de GPS en ese momento) esta no se actualiza sola.
      refreshSelectedPreviewDistance();
    }
  }

  Future<void> _requestBackgroundLocationPermission() async {
    try {
      await PermissionsHelper.requestBackgroundLocationPermission();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  Future<void> refreshLocation() async {
    await _loadLocation();
  }

  // ===== Preview + ruta (delegado a PreviewRouteController) =====

  PreviewSolicitud? get selectedPreview => _previewController.selectedPreview;
  bool get isMapExpanded => _previewController.isMapExpanded;
  Map<String, List<LatLng>> get routePoints => _previewController.routePoints;
  Set<Polyline> get routePolylines => _previewController.routePolylines;
  Set<Marker> get extraMarkers => _previewController.extraMarkers;
  bool get isLoadingPreviewRoute => _previewController.isLoadingPreviewRoute;

  void refreshSelectedPreviewDistance() =>
      _previewController.refreshSelectedPreviewDistance();

  /// Refleja localmente el valor recién contraofertado en la preview abierta,
  /// para que `PrecioOfertaBox` lo muestre de inmediato sin esperar el
  /// snapshot de Firestore.
  void applyLocalContraoferta(double valor) =>
      _previewController.applyLocalContraoferta(valor);

  void selectPreview(PreviewSolicitud preview) =>
      _previewController.selectPreview(preview);

  String? fotoClientePorId(String? clienteId) =>
      _previewController.fotoClientePorId(clienteId);

  Future<void> preloadClientePhoto(String? clienteId) =>
      _previewController.preloadClientePhoto(clienteId);

  void clearPreviewAndRoutes() => _previewController.clearPreviewAndRoutes();

  void setMapExpanded(bool value) => _previewController.setMapExpanded(value);

  void setRoute(String id, List<LatLng> points) =>
      _previewController.setRoute(id, points);

  Future<void> fetchRouteOSRM(String id, LatLng origin, LatLng dest) =>
      _previewController.fetchRouteOSRM(id, origin, dest);

  CameraPosition? getCameraPerspectiveForPreview() =>
      _previewController.getCameraPerspectiveForPreview();

  double calculateBearing(LatLng from, LatLng to) =>
      _previewController.calculateBearing(from, to);

  /// Zoom sugerido para la cámara según la distancia (metros) entre el
  /// conductor y el cliente, usado al centrar la preview de una solicitud.
  double zoomForDistance(double meters) {
    if (meters <= 150) return 17.5;
    if (meters <= 300) return 16.8;
    if (meters <= 600) return 16.0;
    if (meters <= 1200) return 15.0;
    if (meters <= 2500) return 14.0;
    if (meters <= 5000) return 13.0;
    return 12.0;
  }

  /// Asegura que el listener de solicitudes esté activo si el conductor está conectado.
  void ensureSolicitudesSubscription() {
    if (!isConnected) return;
    _solicitudesController.subscribe();
  }

  /// Vigila si CUALQUIER solicitud queda asignada a este conductor (acepta él o
  /// el cliente acepta su contraoferta) y dispara [onAsignadoAMi] para navegar,
  /// sin depender de tener la preview abierta.
  void _subscribeAssignedToMe() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _assignedSub?.cancel();
    // Filtrado por estado en el SERVIDOR: sin el `whereIn` esta suscripción
    // descargaba todas las solicitudes que el conductor hizo alguna vez —
    // historial completo, creciendo para siempre— en cada arranque, solo para
    // encontrar la única activa. El filtro es el mismo conjunto que
    // `SolicitudEstado.isSesionActiva`, que se sigue aplicando abajo.
    _assignedSub = _firestore
        .collection('solicitudes')
        .where('conductor.id', isEqualTo: uid)
        .where(
          'estado',
          whereIn: const [
            SolicitudEstado.asignado,
            SolicitudEstado.enEspera,
            SolicitudEstado.enCamino,
            SolicitudEstado.enRuta,
          ],
        )
        .snapshots()
        .listen(
          (snap) {
            for (final doc in snap.docs) {
              final data = doc.data() as Map<String, dynamic>?;
              final estado = SolicitudEstado.normalize(
                (data?['estado'] ?? data?['status'] ?? '').toString(),
              );
              final activo = SolicitudEstado.isSesionActiva(estado);
              if (activo && !_handledAssigned.contains(doc.id)) {
                _handledAssigned.add(doc.id);
                try {
                  onAsignadoAMi?.call(doc.id);
                } catch (e, st) {
                  ErrorReporter.report(
                    e,
                    st,
                    reason: 'InicioConductorViewModel',
                  );
                }
                break;
              }
            }
          },
          // Sin `onError`, un `permission-denied` (o un índice faltante) mataba
          // el listener en silencio y el conductor dejaba de ser navegado a su
          // viaje sin que nada lo registrara.
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
          },
        );
  }

  void _subscribeConductorStatus() {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _conductorSub?.cancel();
      _conductorSub = _firestore.collection('usuarios').doc(uid).snapshots().listen((
        snap,
      ) {
        if (!snap.exists) return;
        final data = snap.data();
        if (data != null) {
          final previousTipo = _profileController.tipoVehiculoConductor;
          _profileController.hydrateFromConductorDoc(data);
          if (_profileController.tipoVehiculoConductor != previousTipo) {
            // Re-filtrar localmente las solicitudes ya cacheadas con el nuevo
            // tipo de vehículo, sin esperar un nuevo evento de Firestore ni
            // recargar la app (ver cambiar_vehiculo_view.dart).
            _solicitudesController.reprocessLastSnapshot();
          }
        }

        final connected =
            snap.exists &&
            ((snap.data()?['disponible'] == true) ||
                (snap.data()?['conectado'] == true));
        final previously = isConnected;
        isConnected = connected;
        if (!isConnected) {
          // Limpiar estados de solicitudes/previews cuando no está disponible.
          try {
            stopPreviewSolicitudStatusListener();
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
          }
          clearPreviewAndRoutes();
          _solicitudesController.clear();
          // Cancel solicitudes listener when disconnected to avoid processing updates
          try {
            _solicitudesController.stop();
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
          }
          // Desconectado: deja de publicar posición (si no, seguiría
          // apareciendo como candidato con una posición que ya no se mueve).
          _detenerRefrescoUbicacionConectado();
          _safeNotify();
        } else if (!previously && isConnected) {
          // Just became connected: start listening to solicitudes
          try {
            _solicitudesController.subscribe();
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
          }
          _iniciarRefrescoUbicacionConectado();
        }
        _safeNotify();
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  Future<void> toggleConductorConnection() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    isTogglingConnection = true;
    _safeNotify();
    try {
      final docRef = _firestore.collection('usuarios').doc(uid);
      final snap = await docRef.get();
      final data = snap.data();
      final current =
          snap.exists &&
          ((data?['disponible'] == true) || (data?['conectado'] == true));
      final newVal = !current;
      await docRef.set({
        'uid': uid,
        'rol': 'conductor',
        'tipoUsuario': 'conductor',
        'disponible': newVal,
      }, SetOptions(merge: true));
      // The _conductorSub listener will update the local isConnected state
    } catch (e) {
      debugPrint('Error toggling connection: $e');
      rethrow;
    } finally {
      isTogglingConnection = false;
      _safeNotify();
    }
  }

  Future<void> aceptarSolicitud(String solicitudId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('No user logged in');

    // `currentLocation` se carga una sola vez al iniciar el ViewModel (ver
    // `_loadLocation`) y no se refresca sola durante una sesión larga
    // conectado. Si se usa tal cual aquí, la coordenada obsoleta queda
    // persistida como `conductor.lat/lng` en el mismo instante en que pasa a
    // "asignado", y es justo esa coordenada la que usan tanto
    // DriverTripController como TripTrackingViewModel para calcular la
    // primera ruta de recogida (mismo problema ya resuelto para el preview
    // en `fetchRouteOSRM`; aquí faltaba aplicarlo).
    try {
      final fresh = await _trackingService.obtenerUbicacionActual();
      if (fresh != null) {
        currentLocation = LatLng(fresh.latitude, fresh.longitude);
      }
    } catch (_) {
      // Se sigue con `currentLocation` existente como fallback.
    }

    final conductorPayload = _buildConductorPayload(uid);
    final ref = _firestore.collection('solicitudes').doc(solicitudId);
    final conductorRef = _firestore.collection('usuarios').doc(uid);

    await _firestore.runTransaction((tx) async {
      // Leer primero el doc del conductor: si la membresía ya venció (el
      // Timer local en InicioConductorView solo corta si la app sigue
      // abierta), no debe poder tomar viajes aunque su UI todavía no se haya
      // refrescado a "inactivo".
      final conductorSnap = await tx.get(conductorRef);
      final conductorData = conductorSnap.data() ?? <String, dynamic>{};
      final membresiaActiva =
          (conductorData['membresia'] ?? '').toString().toLowerCase() ==
          'activa';
      final vence = conductorData['membresiaVence'];
      final vencida =
          vence is Timestamp && vence.toDate().isBefore(DateTime.now());
      if (!membresiaActiva || vencida) {
        throw StateError(
          'Tu membresía no está activa. Actívala para aceptar viajes.',
        );
      }

      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('La solicitud ya no existe.');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final estado = SolicitudEstado.normalize(
        (data['estado'] ?? data['status'] ?? '').toString(),
      );
      if (estado != SolicitudEstado.buscando) {
        throw StateError('Esta solicitud ya fue tomada por otro conductor.');
      }
      tx.update(ref, {
        'estado': SolicitudEstado.asignado,
        'conductor': conductorPayload,
        'estadoContraoferta': EstadoContraoferta.sinContraoferta,
        'contraoferta': {
          'estado': EstadoContraoferta.sinContraoferta,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'fecha de aceptacion conductor': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Sale del índice de despacho al tomar el viaje, en la MISMA
      // transacción, para que no exista un instante en el que ya tenga viaje
      // pero el reparto lo siga considerando candidato: antes seguía contando
      // como libre para las notificaciones de proximidad y para el mapa de
      // conductores del cliente.
      //
      // Se borra su posición publicada en vez de poner `disponible: false`.
      // `disponible` es la INTENCIÓN del conductor (su toggle online/offline);
      // apagarla acá lo dejaría offline después de cada viaje y tendría que
      // volver a conectarse a mano. La presencia en `conductores_conectados`
      // es lo que significa "despachable ahora", y se restablece sola: el
      // home la vuelve a publicar al montarse y cada 2 min mientras esté
      // conectado.
      tx.delete(_firestore.collection('conductores_conectados').doc(uid));
    });
  }

  Future<void> enviarContraoferta({
    required String solicitudId,
    required double nuevoValor,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('No user logged in');

    // Mismo problema de GPS obsoleto que en `aceptarSolicitud`: una
    // contraoferta también persiste `conductor.lat/lng` y puede terminar en
    // "asignado" si el cliente la acepta, así que necesita ubicación fresca.
    try {
      final fresh = await _trackingService.obtenerUbicacionActual();
      if (fresh != null) {
        currentLocation = LatLng(fresh.latitude, fresh.longitude);
      }
    } catch (_) {
      // Se sigue con `currentLocation` existente como fallback.
    }

    final conductorPayload = _buildConductorPayload(uid);
    final ref = _firestore.collection('solicitudes').doc(solicitudId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('La solicitud ya no existe.');
      }

      final data = snap.data() ?? <String, dynamic>{};
      final estado = SolicitudEstado.normalize(
        (data['estado'] ?? data['status'] ?? '').toString(),
      );
      if (estado == SolicitudEstado.asignado ||
          estado == SolicitudEstado.cancelado) {
        throw StateError('La solicitud ya no permite contraoferta.');
      }

      final ofertaEntry = {
        'estado': EstadoContraoferta.pendienteCliente,
        'valor': nuevoValor,
        'conductor': conductorPayload,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      tx.set(ref, {
        'estado': SolicitudEstado.buscando,
        'estadoContraoferta': EstadoContraoferta.pendienteCliente,
        'updatedAt': FieldValue.serverTimestamp(),
        // Legacy: un solo campo para compatibilidad
        'contraoferta': ofertaEntry,
        // Nuevo: mapa por conductor para ofertas múltiples simultáneas
        'contraofertas': {uid: ofertaEntry},
      }, SetOptions(merge: true));
    });
  }

  /// Formatea un entero como moneda con separador de miles ('.'), ej. 12345 -> "12.345".
  String formatMoneda(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final rev = s.length - i;
      buf.write(s[i]);
      if (rev > 1 && rev % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }

  /// Opciones sugeridas de contraoferta a partir del valor base ofrecido por
  /// el cliente (o un mínimo por defecto si no hay valor base), ordenadas
  /// ascendentemente.
  List<int> contraofertaOpciones(int valorBase) {
    final base = valorBase > 0 ? valorBase : 10000;
    return <int>{
      base + 1000,
      base + 2000,
      base + 3000,
      base + 5000,
      base + 7000,
    }.toList()..sort();
  }

  Map<String, dynamic> _buildConductorPayload(String uid) {
    return {
      'id': uid,
      'nombre': displayName,
      if (photoUrl != null) 'foto': photoUrl,
      'placa': vehiclePlate ?? '',
      if (currentLocation != null) 'lat': currentLocation!.latitude,
      if (currentLocation != null) 'lng': currentLocation!.longitude,
      if (vehiclePhotoUrl != null) 'fotoVehiculo': vehiclePhotoUrl,
      // Rating para que el cliente lo vea en la modal de ofertas.
      'calificacionPromedio': rating,
      'totalCalificaciones': totalRatings,
    };
  }

  Future<void> listenPreviewSolicitudStatus({
    required String solicitudId,
    required Future<void> Function() onCanceladoOrRemoved,
    required Future<void> Function() onAsignado,
  }) async {
    await stopPreviewSolicitudStatusListener();
    _previewStatusHandled = false;

    _previewStatusSub = _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((snap) async {
          try {
            if (_previewStatusHandled) return;

            if (!snap.exists) {
              _previewStatusHandled = true;
              await onCanceladoOrRemoved();
              return;
            }

            final data = snap.data();
            final status = data?['estado'] ?? data?['status'];
            if (status is! String) return;

            final normalizado = SolicitudEstado.normalize(status);
            if (normalizado == SolicitudEstado.cancelado) {
              _previewStatusHandled = true;
              await onCanceladoOrRemoved();
              return;
            }

            // La solicitud ya tiene conductor: solo navegar al viaje si ESE
            // conductor soy yo. Sin esta comprobación, todo conductor con la
            // preview abierta era arrastrado al viaje que ganó otro — su GPS
            // terminaba escribiéndose en un viaje ajeno (o, con las reglas
            // desplegadas, quedaba encerrado en una pantalla de error con
            // `PopScope(canPop: false)` y sin salida). Para él la solicitud
            // simplemente dejó de estar disponible.
            if (SolicitudEstado.isSesionActiva(normalizado) ||
                SolicitudEstado.isTerminal(normalizado)) {
              _previewStatusHandled = true;
              final conductor = data?['conductor'];
              final conductorId = conductor is Map
                  ? (conductor['id'] ?? conductor['uid'])?.toString()
                  : null;
              final esMio =
                  conductorId != null &&
                  conductorId.isNotEmpty &&
                  conductorId == _auth.currentUser?.uid;
              if (esMio && normalizado == SolicitudEstado.asignado) {
                await onAsignado();
              } else {
                await onCanceladoOrRemoved();
              }
              return;
            }
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
          }
        });
  }

  Future<void> stopPreviewSolicitudStatusListener() async {
    final sub = _previewStatusSub;
    _previewStatusSub = null;
    _previewStatusHandled = false;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  /// Centra la cámara del mapa en `currentLocation` si está disponible.
  ///
  /// Pasa el `GoogleMapController` activo y opcionalmente el nivel de zoom.
  Future<void> centerMapOnMarker(
    GoogleMapController controller, {
    double zoom = 15.0,
  }) async {
    if (currentLocation == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentLocation!, zoom: zoom),
        ),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  /// Devuelve un `CameraUpdate` centrado en `currentLocation` o `null` si no hay ubicación.
  CameraUpdate? get cameraUpdateForCurrentLocation {
    if (currentLocation == null) return null;
    return CameraUpdate.newLatLngZoom(currentLocation!, 15.0);
  }

  @override
  void dispose() {
    _disposed = true;
    _detenerRefrescoUbicacionConectado();
    _profileController.dispose();
    try {
      _solicitudesController.dispose();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    try {
      _conductorSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    try {
      _previewStatusSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    try {
      _assignedSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
    SoporteNotificationService.instance.detenerEscuchaUsuario();
    currentLocationNotifier.dispose();
    selectedPreviewNotifier.dispose();
    extraMarkersNotifier.dispose();
    routePolylinesNotifier.dispose();
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    _syncMapNotifiers();
    notifyListeners();
  }

  /// Guarda la ubicación del conductor en conductores_conectados.
  Future<void> guardarUbicacionConectado(LatLng location) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('conductores_conectados').doc(uid).set({
        'ubicacion': {'lat': location.latitude, 'lng': location.longitude},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }

  /// Cada cuánto se refresca la posición publicada en
  /// `conductores_conectados`. 2 min es un compromiso: suficientemente fresco
  /// para el radio de 3 km que usa el reparto de solicitudes, y lo bastante
  /// espaciado para no castigar batería ni cuota de escrituras.
  static const Duration _intervaloRefrescoUbicacion = Duration(minutes: 2);

  /// Mínimo desplazamiento para escribir. Evita reescribir el documento
  /// cuando el conductor está detenido (semáforo, esperando en un punto).
  static const double _minMetrosParaRepublicar = 100;

  Timer? _ubicacionConectadoTimer;
  LatLng? _ultimaUbicacionPublicada;

  /// Mantiene fresca la posición en `conductores_conectados` mientras el
  /// conductor está conectado.
  ///
  /// Antes solo se escribía UNA vez, al arrancar la pantalla: el documento
  /// quedaba congelado toda la sesión. Ahora que el reparto de solicitudes
  /// (`onNuevaSolicitudCreada`) decide a quién notificar con ese dato, una
  /// posición vieja significa avisar al conductor equivocado — o no avisar a
  /// nadie.
  void _iniciarRefrescoUbicacionConectado() {
    _ubicacionConectadoTimer?.cancel();
    _ubicacionConectadoTimer = Timer.periodic(
      _intervaloRefrescoUbicacion,
      (_) => unawaited(publicarUbicacionSiCambio()),
    );
  }

  void _detenerRefrescoUbicacionConectado() {
    _ubicacionConectadoTimer?.cancel();
    _ubicacionConectadoTimer = null;
    _ultimaUbicacionPublicada = null;
  }

  @visibleForTesting
  Future<void> publicarUbicacionSiCambio() async {
    if (_disposed || !isConnected) return;
    try {
      final pos = await _trackingService.obtenerUbicacionActual();
      if (pos == null || _disposed || !isConnected) return;
      final actual = LatLng(pos.latitude, pos.longitude);

      final previa = _ultimaUbicacionPublicada;
      if (previa != null &&
          MapHelper.distanceMeters(previa, actual) < _minMetrosParaRepublicar) {
        return;
      }

      currentLocation = actual;
      await guardarUbicacionConectado(actual);
      _ultimaUbicacionPublicada = actual;
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'InicioConductorViewModel');
    }
  }
}
