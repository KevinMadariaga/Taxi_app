import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/ubicacion_resultado.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/core/services/ubicacion_servicio.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

class InicioClienteViewModel extends ChangeNotifier {
  // --- Estado principal ---
  String search = '';
  String _clientName = 'Cliente';
  String? _clientId;
  bool _isLoadingLocation = false;
  bool _isLoadingFavoritos = false;
  LatLng? _currentLocation;
  bool _favoritosLoaded = false;
  bool _disposed = false;
  // Último uid persistido en disco; evita reescrituras redundantes en cada
  // emisión del authStateChanges (que dispara con el mismo uid al recargar).
  String? _persistedUid;
  // Caché de última ubicación: evita mostrar "Buscando ubicación" si el GPS
  // devuelve la misma posición que ya teníamos guardada.
  bool _ubicacionNueva = false;
  static const double _umbralCambioMetros = 35.0;
  static const String _kLastLat = 'cli_last_lat';
  static const String _kLastLng = 'cli_last_lng';

  Set<Marker> _conductoresMarkers = <Marker>{};
  BitmapDescriptor? _taxiIcon;
  List<UbicacionResultado> _favoritos = [];

  // --- ValueNotifiers dedicados para el mapa / loader ---
  // Vía adicional para que el widget del GoogleMap y el overlay de carga se
  // reconstruyan de forma aislada (AnimatedBuilder) sin depender del rebuild
  // completo disparado por el ChangeNotifier general del VM. No reemplazan
  // los campos ni los notifyListeners() existentes: otros flujos del VM
  // siguen dependiendo de ellos.
  final ValueNotifier<LatLng?> currentLocationNotifier =
      ValueNotifier<LatLng?>(null);
  final ValueNotifier<Set<Marker>> conductoresMarkersNotifier =
      ValueNotifier<Set<Marker>>(<Marker>{});
  final ValueNotifier<bool> isLoadingLocationNotifier = ValueNotifier<bool>(
    false,
  );

  // --- Getters públicos ---
  String get clientName => _clientName;
  String? get clientId => _clientId;
  bool get isLoadingLocation => _isLoadingLocation;
  bool get isLoadingFavoritos => _isLoadingFavoritos;
  LatLng? get currentLocation => _currentLocation;

  /// `true` si la última carga detectó una ubicación nueva (distinta a la
  /// cacheada). La vista lo usa para mostrar "Ubicación encontrada" solo
  /// cuando realmente hubo un cambio.
  bool get ubicacionFueActualizada => _ubicacionNueva;
  Set<Marker> get conductoresMarkers => _conductoresMarkers;
  List<UbicacionResultado> get favoritos => List.unmodifiable(_favoritos);

  // --- Servicios y subscripciones ---
  final FirebaseService _firebaseService = FirebaseService();
  final UbicacionService _ubicacionService = UbicacionService();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String?>? _cachedNameSub;
  StreamSubscription<QuerySnapshot>? _conductoresSub;

  // --- Inicialización y ciclo de vida ---
  Future<void> init() async {
    _listenAuthChanges();
    _listenCachedName();
    await _inicializarConductoresConectados();
  }

  void _listenAuthChanges() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        _clientId = user.uid;
        _clientName = await _obtenerNombreCliente(user);
        // Solo persistir en disco si el uid cambió (evita escrituras repetidas
        // de los mismos valores en cada recarga / emisión del stream).
        if (_persistedUid != user.uid) {
          await SessionHelper.saveSession('cliente', user.uid);
          _persistedUid = user.uid;
        }
        await cargarFavoritosUnaVez();
        SoporteNotificationService.instance.iniciarEscuchaUsuario(user.uid);
        if (!_disposed) notifyListeners();
      } else {
        _clientId = null;
        _favoritos = [];
        _favoritosLoaded = false;
        SoporteNotificationService.instance.detenerEscuchaUsuario();
        await _cargarClienteDesdeCache();
        if (!_disposed) notifyListeners();
      }
    });
  }

  /// Reinicia el listener de conductores conectados (marcadores del mapa).
  /// Se usa tras un "mini reload" por background prolongado, para descartar
  /// cualquier suscripción de Firestore que haya quedado inactiva.
  Future<void> reiniciarConductoresConectados() =>
      _inicializarConductoresConectados();

  /// Fuerza una recarga de la ubicación actual del GPS, ignorando el umbral
  /// de "¿es una ubicación nueva?" (a diferencia de [cargarUbicacionActual]).
  /// Se usa tras volver de background prolongado, donde el usuario pudo
  /// desplazarse y la última posición cacheada/mostrada ya no es válida.
  Future<void> forzarRecargaUbicacion() async {
    LatLng? loc;
    try {
      loc = await _ubicacionService.obtenerUbicacionActual();
    } catch (e) {
      debugPrint('Error obteniendo ubicación actual: $e');
    }
    if (loc == null) return;

    _isLoadingLocation = true;
    isLoadingLocationNotifier.value = true;
    if (!_disposed) notifyListeners();
    try {
      _currentLocation = loc;
      currentLocationNotifier.value = loc;
      await _guardarUbicacionCliente(loc);
      await _guardarUbicacionCache(loc);
      _ubicacionNueva = true;
    } catch (e) {
      debugPrint('Error guardando ubicación: $e');
    } finally {
      _isLoadingLocation = false;
      isLoadingLocationNotifier.value = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _inicializarConductoresConectados() async {
    try {
      _taxiIcon = await MapHelper.loadMarkerIcon(
        'assets/img/carito.png',
        size: const Size(50, 50),
      );
    } catch (e) {
      debugPrint('Error cargando icono de taxi: $e');
    }

    _conductoresSub?.cancel();
    _conductoresSub = FirebaseFirestore.instance
        .collection('conductores')
        .where('activos', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            final markers = <Marker>{};
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final geo = _extractConductorLocation(data);
              if (geo != null) {
                markers.add(
                  Marker(
                    markerId: MarkerId(doc.id),
                    position: geo,
                    icon: _taxiIcon ?? BitmapDescriptor.defaultMarker,
                    infoWindow: const InfoWindow(title: 'Taxi disponible'),
                  ),
                );
              }
            }
            _conductoresMarkers = markers;
            conductoresMarkersNotifier.value = markers;
            if (!_disposed) notifyListeners();
          },
          onError: (e) {
            debugPrint('Error escuchando conductores conectados: $e');
          },
        );
  }

  Future<void> cargarFavoritosUnaVez() async {
    if (_favoritosLoaded) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isLoadingFavoritos = true;
    if (!_disposed) notifyListeners();

    try {
      final userFavSnapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .collection('favoritos')
          .get();

      QuerySnapshot<Map<String, dynamic>> snapshot = userFavSnapshot;

      // Compatibilidad con estructura legacy mientras se migra la data.
      if (snapshot.docs.isEmpty) {
        snapshot = await FirebaseFirestore.instance
            .collection('ubicaciones')
            .where('userId', isEqualTo: user.uid)
            .get();
      }

      _favoritos = snapshot.docs.map((doc) {
        final data = doc.data();
        final nombre = (data['nombre'] ?? '') as String;
        final direccion = (data['direccion'] ?? '') as String;
        final geo = data['ubicacion'] as GeoPoint?;
        if (geo == null) {
          return UbicacionResultado(
            location: null,
            nombre: nombre.isNotEmpty ? nombre : 'Favorito',
            direccion: direccion.isNotEmpty ? direccion : nombre,
          );
        }
        return UbicacionResultado(
          location: LatLng(geo.latitude, geo.longitude),
          nombre: nombre.isNotEmpty ? nombre : 'Favorito',
          direccion: direccion.isNotEmpty ? direccion : nombre,
        );
      }).toList();

      _favoritosLoaded = true;
    } catch (e) {
      debugPrint('Error cargando favoritos: $e');
    } finally {
      _isLoadingFavoritos = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _listenCachedName() {
    try {
      _cachedNameSub = SessionHelper.cachedNameStream.listen((n) {
        if (n != null && n.trim().isNotEmpty) {
          _clientName = n.trim();
          if (!_disposed) notifyListeners();
        }
      });
      // Aplicar valor actual si existe
      SessionHelper.getCachedName()
          .then((n) {
            if (n != null && n.trim().isNotEmpty) {
              _clientName = n.trim();
              if (!_disposed) notifyListeners();
            }
          })
          .catchError((_) {});
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
  }

  Future<String> _obtenerNombreCliente(User user) async {
    String name = 'Cliente';
    try {
      // 0. Intentar leer primero desde la nueva coleccion unificada 'usuarios'.
      final userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        final dynamic maybeName = userData != null ? userData['nombre'] : null;
        if (maybeName is String && maybeName.trim().isNotEmpty) {
          name = maybeName.trim();
        }
      }

      // 1. Intentar leer el nombre desde la colección 'cliente' en Firestore
      if (name == 'Cliente') {
        final doc = await FirebaseFirestore.instance
            .collection('cliente')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final dynamic maybeName = data != null ? data['nombre'] : null;
          if (maybeName is String && maybeName.trim().isNotEmpty) {
            name = maybeName.trim();
          }
        }
      }
      // 2. Si no hay nombre en Firestore, usar cache/displayName/email
      if (name == 'Cliente') {
        final cached = await SessionHelper.getCachedName();
        if (cached != null && cached.trim().isNotEmpty) {
          name = cached.trim();
        } else if (user.displayName != null &&
            user.displayName!.trim().isNotEmpty) {
          name = user.displayName!.trim();
        } else if (user.email != null && user.email!.contains('@')) {
          final namePart = user.email!.split('@').first;
          name = namePart.isNotEmpty
              ? '${namePart[0].toUpperCase()}${namePart.substring(1)}'
              : 'Cliente';
        }
      }
    } catch (e) {
      debugPrint('Error leyendo nombre de cliente: $e');
    }
    // Cachear el nombre resuelto para que las recargas siguientes sean
    // instantáneas (hydrateFromUid lo usa sin volver a consultar Firestore).
    if (name != 'Cliente') {
      try {
        await SessionHelper.saveCachedName(name);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
      }
    }
    return name;
  }

  /// Hidratación rápida al entrar a la pantalla: fija el uid recibido tras el
  /// login y muestra el nombre en cache al instante. La lectura autoritativa
  /// desde Firestore la hace el listener de auth ([_listenAuthChanges]), por lo
  /// que aquí NO se consulta Firestore: evita una lectura duplicada en cada
  /// recarga de la clase.
  Future<void> hydrateFromUid(String uid) async {
    _clientId = uid;
    try {
      final cached = await SessionHelper.getCachedName();
      if (cached != null && cached.trim().isNotEmpty) {
        _clientName = cached.trim();
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _cargarClienteDesdeCache() async {
    try {
      final savedUid = await SessionHelper.getUserUid();
      if (savedUid != null && savedUid.isNotEmpty) {
        _clientId = savedUid;
        try {
          final cached = await SessionHelper.getCachedName();
          if (cached != null && cached.trim().isNotEmpty) {
            _clientName = cached.trim();
          }
        } catch (e) {
          debugPrint('Error leyendo nombre desde session cache: $e');
        }
      }
    } catch (e) {
      debugPrint('Error accediendo SessionHelper: $e');
    }
  }

  /// Actualiza la ubicación local y en Firestore si hay cliente
  Future<void> updateLocation(LatLng loc) async {
    _isLoadingLocation = true;
    isLoadingLocationNotifier.value = true;
    _currentLocation = loc;
    currentLocationNotifier.value = loc;
    if (!_disposed) notifyListeners();
    try {
      await _guardarUbicacionCliente(loc);
    } catch (e) {
      debugPrint('Error guardando ubicacion: $e');
    } finally {
      _isLoadingLocation = false;
      isLoadingLocationNotifier.value = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> cargarUbicacionActual() async {
    _ubicacionNueva = false;

    // 1. Mostrar de inmediato la última ubicación cacheada (sin loader).
    final cache = await _leerUbicacionCache();
    if (cache != null && _currentLocation == null) {
      _currentLocation = cache;
      currentLocationNotifier.value = cache;
      if (!_disposed) notifyListeners();
    }

    // 2. Pedir ubicación al GPS.
    LatLng? loc;
    try {
      loc = await _ubicacionService.obtenerUbicacionActual();
    } catch (e) {
      debugPrint('Error obteniendo ubicación actual: $e');
    }
    if (loc == null) return;

    // 3. Comparar con la cacheada. Si es la misma → mantenerla, sin loader.
    final base = cache ?? _currentLocation;
    final esNueva =
        base == null ||
        Geolocator.distanceBetween(
              base.latitude,
              base.longitude,
              loc.latitude,
              loc.longitude,
            ) >
            _umbralCambioMetros;

    if (!esNueva) {
      _currentLocation = base;
      currentLocationNotifier.value = base;
      try {
        await _guardarUbicacionCliente(base!);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
      }
      return;
    }

    // 4. Ubicación nueva → mostrar "Buscando ubicación" y actualizar.
    _isLoadingLocation = true;
    isLoadingLocationNotifier.value = true;
    if (!_disposed) notifyListeners();
    try {
      _currentLocation = loc;
      currentLocationNotifier.value = loc;
      await _guardarUbicacionCliente(loc);
      await _guardarUbicacionCache(loc);
      _ubicacionNueva = true;
    } catch (e) {
      debugPrint('Error guardando ubicación: $e');
    } finally {
      _isLoadingLocation = false;
      isLoadingLocationNotifier.value = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<LatLng?> _leerUbicacionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_kLastLat);
      final lng = prefs.getDouble(_kLastLng);
      if (lat != null && lng != null) return LatLng(lat, lng);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
    return null;
  }

  Future<void> _guardarUbicacionCache(LatLng loc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kLastLat, loc.latitude);
      await prefs.setDouble(_kLastLng, loc.longitude);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
  }

  Future<void> _guardarUbicacionCliente(LatLng loc) async {
    String? cid = _clientId ?? FirebaseAuth.instance.currentUser?.uid;
    if (cid == null || cid.isEmpty) {
      cid = await SessionHelper.getUserUid();
    }
    if (cid != null && cid.isNotEmpty) {
      await _firebaseService.guardarUbicacionCliente(
        clienteId: cid,
        position: loc,
      );
    }
  }

  Future<String> obtenerDireccionDesdeCoordenadas(LatLng coord) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coord.latitude,
        coord.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final name = p.name?.trim() ?? '';
        final street = p.street?.trim() ?? '';
        final subLocality = p.subLocality?.trim() ?? '';
        final locality = p.locality?.trim() ?? '';
        final parts = <String>[
          name,
          street,
          subLocality,
          locality,
        ].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          return parts.take(2).join(', ');
        }
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
    return '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    try {
      _cachedNameSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
    try {
      _conductoresSub?.cancel();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'inicio_cliente_viewmodel');
    }
    SoporteNotificationService.instance.detenerEscuchaUsuario();
    currentLocationNotifier.dispose();
    conductoresMarkersNotifier.dispose();
    isLoadingLocationNotifier.dispose();
    super.dispose();
  }

  // --- Métodos utilitarios ---
  void updateSearch(String value) {
    search = value;
    if (!_disposed) notifyListeners();
  }

  LatLng? _extractConductorLocation(Map<String, dynamic> data) {
    final ubicacion = data['ubicacion'];
    if (ubicacion is GeoPoint) {
      return LatLng(ubicacion.latitude, ubicacion.longitude);
    }

    if (ubicacion is Map) {
      final lat = (ubicacion['lat'] ?? ubicacion['latitude']) as num?;
      final lng =
          (ubicacion['lng'] ?? ubicacion['longitude'] ?? ubicacion['longitud'])
              as num?;
      if (lat != null && lng != null) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    final lat = (data['lat'] ?? data['latitude']) as num?;
    final lng = (data['lng'] ?? data['longitude'] ?? data['longitud']) as num?;
    if (lat != null && lng != null) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }

    return null;
  }
}
