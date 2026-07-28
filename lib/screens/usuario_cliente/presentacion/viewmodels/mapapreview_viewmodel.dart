import 'dart:ui';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/helpers/map_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// ViewModel unificado para:
/// - Selección/previsualización de destino (pantalla de mapa con pin centrado).
/// - Previsualización con dos marcadores (origen y destino) antes de confirmar la solicitud.
class MapapreviewViewModel extends ChangeNotifier {
  /// Constructor para la vista de previsualización con dos marcadores
  /// (usa origen y destino reales).
  MapapreviewViewModel({required this.origen, required this.destino})
    : _center = origen.position,
      _initialDireccion = origen.title,
      _origenLocation = origen.position,
      _origenDireccion = origen.title;

  /// Constructor para la vista de selección de destino.
  ///
  /// Se basa en una ubicación inicial y, opcionalmente, en datos de origen.
  MapapreviewViewModel.forSelection({
    required LatLng initialLocation,
    String? initialDireccion,
    LatLng? origenLocation,
    String? origenDireccion,
  }) : origen = LocationModel(
         position: origenLocation ?? initialLocation,
         title: origenDireccion ?? initialDireccion,
       ),
       destino = LocationModel(
         position: initialLocation,
         title: initialDireccion,
       ),
       _center = initialLocation,
       _initialDireccion = initialDireccion,
       _origenLocation = origenLocation,
       _origenDireccion = origenDireccion;

  /// Modelo de la ubicación de origen (para la vista de previsualización).
  final LocationModel origen;

  /// Modelo de la ubicación de destino (para la vista de previsualización).
  final LocationModel destino;

  // --- Estado para selección de destino ---

  /// Centro actual del mapa (coincide con la posición del indicador en selección).
  LatLng _center;

  /// Dirección legible resuelta para el centro actual.
  String? _currentAddress;

  /// Dirección inicial pasada desde la pantalla anterior (si existe).
  final String? _initialDireccion;

  /// Información opcional sobre el origen, que puede usarse para etiquetas.
  final LatLng? _origenLocation;
  final String? _origenDireccion;

  // Getters expuestos a las vistas de selección

  LatLng get center => _center;

  String? get currentAddress => _currentAddress;

  String? get initialDireccion => _initialDireccion;

  LatLng? get origenLocation => _origenLocation;

  String? get origenDireccion => _origenDireccion;

  /// Método de pago seleccionado.
  String metodoPago = 'Efectivo';

  /// Comentario adicional del cliente para el conductor.
  String comentario = '';

  /// Tipo de vehículo seleccionado por el cliente.
  VehicleType tipoVehiculo = VehicleType.carro;

  /// Valor del servicio dependiendo de la hora y el tipo de vehículo.
  late String valorServicio;

  /// Polilíneas que representan la ruta.
  Set<Polyline> polylines = {};

  /// Indica si se está creando la solicitud.
  bool isSubmitting = false;

  /// Indica si se está creando la ruta.
  bool isLoadingRoute = false;

  /// Distancia aproximada de la ruta, en km (opcional, por si se quiere mostrar).
  double? routeDistanceKm;

  final MapService _mapService = const MapService();

  /// Umbral de tiempo en background a partir del cual, al reanudar la app,
  /// se considera que la ubicación/ruta pudo quedar desactualizada y debe
  /// forzarse una recarga.
  static const Duration resumeReloadThreshold = Duration(seconds: 12);

  /// Indica si, dado el instante en que la app fue pausada y el instante
  /// actual, corresponde recargar el mapa/ruta al reanudar (regla de
  /// negocio pura, sin dependencia de `BuildContext`).
  bool shouldReloadOnResume(DateTime pausedAt, DateTime now) {
    return now.difference(pausedAt) >= resumeReloadThreshold;
  }

  /// Texto de coordenadas legible como fallback cuando no hay dirección
  /// resuelta por reverse geocoding.
  String coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  /// Construye una dirección legible (calle, sector, localidad,
  /// departamento) a partir de un [Placemark] de reverse geocoding.
  /// Devuelve cadena vacía si no hay segmentos disponibles; el llamador
  /// decide el fallback (p.ej. [coordsText]).
  String buildAddressFromPlacemark(Placemark p) {
    return [
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
    ].where((s) => s != null && s.isNotEmpty).join(', ');
  }

  String _normalizeLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isGenericOriginLabel(String? value) {
    if (value == null) return true;
    final normalized = _normalizeLabel(value);
    if (normalized.isEmpty) return true;
    const genericLabels = {
      'tu ubicacion',
      'ubicacion',
      'ubicacion actual',
      'mi ubicacion',
      'origen',
    };
    return genericLabels.contains(normalized);
  }

  Future<String> _resolveOrigenAddressForSolicitud() async {
    final origenPos = origen.position;

    final subtitle = origen.subtitle?.trim();
    if (!_isGenericOriginLabel(subtitle)) {
      final formatted = formatAddress(subtitle);
      return formatted.isNotEmpty ? formatted : subtitle!;
    }

    final title = origen.title?.trim();
    if (!_isGenericOriginLabel(title)) {
      final formatted = formatAddress(title);
      return formatted.isNotEmpty ? formatted : title!;
    }

    return _resolveAddressFromCoordinates(origenPos);
  }

  Future<String> _resolveAddressFromCoordinates(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final resolved = _buildFriendlyFromPlacemark(placemarks.first);
        if (resolved.trim().isNotEmpty) return resolved.trim();
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'mapapreview_viewmodel');
    }

    return coordsText(position);
  }

  String _resolveDestinoAddressForSolicitud() {
    final subtitle = formatAddress(destino.subtitle);
    if (subtitle.isNotEmpty) return subtitle;

    final title = formatAddress(destino.title);
    if (title.isNotEmpty) return title;

    return coordsText(destino.position);
  }

  String? _firstNonEmptyValue(Map<String, dynamic>? source, List<String> keys) {
    if (source == null) return null;
    for (final key in keys) {
      final raw = source[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }
    return null;
  }

  double _parseValorServicio() {
    final digits = valorServicio.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return double.tryParse(digits) ?? 0;
  }

  void setValorServicio(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;

    final normalized = int.tryParse(digits)?.toString();
    if (normalized == null || normalized.isEmpty) return;
    if (valorServicio == normalized) return;

    valorServicio = normalized;
    notifyListeners();
  }

  /// Calcula el valor del servicio según la hora y el tipo de vehículo.
  void _calcularValorServicio() {
    final hora = DateTime.now().hour;
    final esNoche = hora >= 18 || hora < 6;
    valorServicio = esNoche
        ? tipoVehiculo.basePriceNoche.toString()
        : tipoVehiculo.basePriceDia.toString();
  }

  /// Cambia el tipo de vehículo y recalcula el valor base del servicio.
  void setTipoVehiculo(VehicleType tipo) {
    if (tipoVehiculo == tipo) return;
    tipoVehiculo = tipo;
    _calcularValorServicio();
    notifyListeners();
  }

  Future<void> init() async {
    _calcularValorServicio();
    isLoadingRoute = true;
    notifyListeners();
    await _buildRouteFollowingRoads();
    isLoadingRoute = false;
    notifyListeners();
  }

  /// Actualiza el centro del mapa cuando la cámara se mueve (solo en selección).
  void updateCameraCenter(LatLng newCenter) {
    _center = newCenter;
    // No notificamos inmediatamente para no redibujar en cada frame de movimiento.
    // La vista se redibuja cuando termine el movimiento y se resuelva la nueva dirección.
  }

  /// Resuelve una dirección legible para el centro actual del mapa (solo en selección).
  Future<void> reverseGeocodeCenter() async {
    try {
      final placemarks = await placemarkFromCoordinates(
        _center.latitude,
        _center.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = _buildFriendlyFromPlacemark(p);
        _currentAddress = direccion.isNotEmpty ? direccion : null;
      } else {
        _currentAddress = null;
      }
    } catch (_) {
      _currentAddress = null;
    }
    notifyListeners();
  }

  /// Formatea una dirección para omitir el texto "Ocaña, Norte de Santander"
  /// y dejar solo las partes más relevantes.
  String formatAddress(String? address) {
    if (address == null || address.trim().isEmpty) return '';
    final pattern = RegExp(
      r',?\s*Oca[nñ]a,?\s*Norte de Santander',
      caseSensitive: false,
      unicode: true,
    );
    var result = address.replaceAll(pattern, '');
    // Eliminar comas/espacios sobrantes al final
    result = result.replaceAll(RegExp(r',\s*\$'), '');
    result = result.trim();
    // Abreviar: tomar hasta 2 segmentos principales
    final parts = result
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return parts.take(2).join(', ');
  }

  /// Construye una dirección amigable a partir de un Placemark.
  String _buildFriendlyFromPlacemark(Placemark p) {
    final name = p.name?.trim() ?? '';
    final street = p.street?.trim() ?? '';
    final subLocality = p.subLocality?.trim() ?? '';
    final locality = p.locality?.trim() ?? '';

    if (name.isNotEmpty && street.isNotEmpty) {
      return formatAddress('$name, $street');
    }
    if (street.isNotEmpty && locality.isNotEmpty) {
      return formatAddress('$street, $locality');
    }
    // fallback: preferir cualquier dos partes no vacías
    final parts = [
      name,
      street,
      subLocality,
      locality,
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return formatAddress(parts.take(2).join(', '));
  }

  /// Cambiar método de pago.
  void setMetodoPago(String value) {
    if (metodoPago == value) return;
    metodoPago = value;
    notifyListeners();
  }

  void setComentario(String value) {
    final next = value.trim();
    if (comentario == next) return;
    comentario = next;
    notifyListeners();
  }

  double calculateBearing(LatLng from, LatLng to) =>
      MapHelper.bearingDegrees(from, to);

  /// Cámara con perspectiva 3D desde el origen (ubicación actual del
  /// cliente) hacia el destino: ancla en el origen y rota el mapa para que
  /// "arriba" apunte hacia el destino. El zoom se ajusta según la distancia
  /// real entre ambos puntos para no cortar el destino fuera de pantalla
  /// cuando está lejos.
  CameraPosition? get cameraPerspective {
    final ori = origen.position;
    final dest = destino.position;
    final bearing = calculateBearing(ori, dest);
    final distance = MapHelper.distanceMeters(ori, dest);
    return CameraPosition(
      target: ori,
      bearing: bearing,
      tilt: 10.0,
      zoom: _zoomForDistance(distance),
    );
  }

  double _zoomForDistance(double meters) {
    if (meters <= 150) return 17.5;
    if (meters <= 300) return 16.8;
    if (meters <= 600) return 16.0;
    if (meters <= 1200) return 15.0;
    if (meters <= 2500) return 14.0;
    if (meters <= 5000) return 13.0;
    return 12.0;
  }

  /// Intenta trazar la ruta real por calles; si falla, usa un fallback matematico.
  Future<void> _buildRouteFollowingRoads() async {
    final o = origen.position;
    final d = destino.position;

    try {
      final points = await _mapService.getRoutePolyline(o, d);

      if (points.isNotEmpty) {
        polylines = {
          _mapService.createPolyline(
            id: 'route',
            points: points,
            color: const Color(0xFFFAC001),
            width: 5,
            geodesic: true,
          ),
        };

        // Estimación de distancia basada en los puntos de la polilínea física
        routeDistanceKm =
            _mapService.calcularDistanciaPolyline(points) / 1000.0;

        notifyListeners();
        return;
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'mapapreview_viewmodel');
    }

    _buildRouteWithMathFallback();
  }

  /// Fallback matematico cuando no se puede obtener una ruta vial.
  void _buildRouteWithMathFallback() {
    final o = origen.position;
    final d = destino.position;
    final straightMeters = MapHelper.distanceMeters(o, d);
    final segments = straightMeters < 1200
        ? 24
        : straightMeters < 4000
        ? 36
        : 48;

    final points = _interpolateRoute(o, d, segments: segments);
    polylines = {
      _mapService.createPolyline(
        id: 'route',
        points: points,
        color: const Color(0xFFFAC001),
        width: 5,
        geodesic: true,
      ),
    };

    final distanceMeters = MapHelper.routeDistanceMeters(points);
    routeDistanceKm = distanceMeters / 1000.0;
    notifyListeners();
  }

  List<LatLng> _interpolateRoute(
    LatLng origin,
    LatLng destination, {
    int segments = 20,
  }) {
    final safeSegments = math.max(2, segments);
    final points = <LatLng>[];

    final dLat = destination.latitude - origin.latitude;
    final dLng = destination.longitude - origin.longitude;
    final distance = math.sqrt((dLat * dLat) + (dLng * dLng));

    // Curva suave perpendicular a la recta O->D para trazar mejor la ruta.
    final normalLat = distance == 0 ? 0.0 : -dLng / distance;
    final normalLng = distance == 0 ? 0.0 : dLat / distance;
    final maxCurve = distance * 0.08;

    for (int i = 0; i <= safeSegments; i++) {
      final t = i / safeSegments;
      final baseLat =
          origin.latitude + (destination.latitude - origin.latitude) * t;
      final baseLng =
          origin.longitude + (destination.longitude - origin.longitude) * t;

      // Onda senoidal para no salir en extremos y curvar en la mitad.
      final curveFactor = math.sin(math.pi * t) * maxCurve;
      final lat = baseLat + (normalLat * curveFactor);
      final lng = baseLng + (normalLng * curveFactor);
      points.add(LatLng(lat, lng));
    }

    return points;
  }

  /// Crea la solicitud en Firestore y devuelve el id generado,
  /// o null si hubo un error.
  Future<String?> crearSolicitud() async {
    if (isSubmitting) return null;
    isSubmitting = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final clienteId = user?.uid.trim();
      if (clienteId == null || clienteId.isEmpty) {
        return null;
      }

      Map<String, dynamic>? clienteDocData;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(clienteId)
            .get();
        if (doc.exists) {
          clienteDocData = doc.data();
        }
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'mapapreview_viewmodel');
      }

      String? clienteNombre = user?.displayName;

      // Si no hay displayName, intentar leer el nombre canónico desde 'cliente'.
      if (clienteNombre == null || clienteNombre.trim().isEmpty) {
        clienteNombre = _firstNonEmptyValue(clienteDocData, const [
          'nombre',
          'name',
          'displayName',
        ]);
      }

      // Fallback final: usar el email para derivar un nombre legible.
      if ((clienteNombre == null || clienteNombre.trim().isEmpty) &&
          user?.email != null) {
        final part = user!.email!.split('@').first;
        final formatted = part.replaceAll(RegExp(r'[._\-+]'), ' ');
        final words = formatted
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .map((w) {
              return w.length == 1
                  ? w.toUpperCase()
                  : '${w[0].toUpperCase()}${w.substring(1)}';
            })
            .join(' ');
        clienteNombre = words.isNotEmpty ? words : null;
      }

      final origenPos = origen.position;
      final origenAddress = await _resolveOrigenAddressForSolicitud();
      final destinoAddress = _resolveDestinoAddressForSolicitud();

      // Prioriza la foto que el cliente subió en su perfil (Firestore
      // 'usuarios/{uid}') sobre la del proveedor de Auth (Google/Apple):
      // si el cliente completó su perfil con una foto propia, esa es la que
      // debe verse en la preview del conductor, no la del Gmail cacheada en
      // FirebaseAuth.currentUser.photoURL.
      String? clientePhotoUrl = _firstNonEmptyValue(clienteDocData, const [
        'foto',
        'fotoUrl',
        'photo',
        'photoUrl',
      ]);
      if (clientePhotoUrl == null || clientePhotoUrl.trim().isEmpty) {
        clientePhotoUrl = user?.photoURL;
      }

      final resolvedClienteNombre =
          (clienteNombre == null || clienteNombre.trim().isEmpty)
          ? 'Cliente'
          : clienteNombre.trim();
      final resolvedClientePhotoUrl = clientePhotoUrl?.trim() ?? '';
      final metodoPagoSanitizado = metodoPago.trim().isEmpty
          ? 'Efectivo'
          : metodoPago.trim();
      final comentarioSanitizado = comentario.trim();
      final valorServicioNumerico = _parseValorServicio();

      // Verificar si ya existe una solicitud activa para este cliente.
      try {
        final existing = await FirebaseFirestore.instance
            .collection('solicitudes')
            .where('cliente.id', isEqualTo: clienteId)
            .where(
              'estado',
              whereIn: [
                SolicitudEstado.buscando,
                'pending',
                'pendiente',
                SolicitudEstado.asignado,
                SolicitudEstado.enEspera,
                SolicitudEstado.enCamino,
                SolicitudEstado.enRuta,
              ],
            )
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          return existing.docs.first.id;
        }
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'mapapreview_viewmodel');
      }

      final solicitud = <String, dynamic>{
        'cliente': {
          'id': clienteId,
          'nombre': resolvedClienteNombre,
          'foto': resolvedClientePhotoUrl,
          'ubicacion': {
            'lat': origenPos.latitude,
            'lng': origenPos.longitude,
            'direccion': origenAddress,
          },
        },
        'origen': {
          'lat': origenPos.latitude,
          'lng': origenPos.longitude,
          'address': origenAddress,
          'title': origenAddress,
        },
        'ubicacion_inicial': GeoPoint(origenPos.latitude, origenPos.longitude),

        'destino': {
          'direccion': destinoAddress,
          'lat': destino.position.latitude,
          'lng': destino.position.longitude,
        },
        'estado': SolicitudEstado.buscando,
        'tipoVehiculo': tipoVehiculo.firestoreKey,
        'metodoPago': metodoPagoSanitizado,
        'comentario': comentarioSanitizado,
        'valorServicioPropuesto': valorServicioNumerico,
        'estadoContraoferta': 'sin_contraoferta',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'tarifa': {
          'total': valorServicioNumerico,
          'propuestaCliente': valorServicioNumerico,
        },
        'contraoferta': {'estado': 'sin_contraoferta', 'valor': null},
      };

      final docRef = await FirebaseFirestore.instance
          .collection('solicitudes')
          .add(solicitud);
      return docRef.id;
    } catch (_) {
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
