import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/helper/map_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/services/map_service.dart';

/// ViewModel unificado para:
/// - Selección/previsualización de destino (pantalla de mapa con pin centrado).
/// - Previsualización con dos marcadores (origen y destino) antes de confirmar la solicitud.
class MapapreviewViewModel extends ChangeNotifier {
  /// Constructor para la vista de previsualización con dos marcadores
  /// (usa origen y destino reales).
  MapapreviewViewModel({
    required this.origen,
    required this.destino,
  })  : _center = origen.position,
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
  })  : origen = LocationModel(
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

  /// Valor del servicio dependiendo de la hora.
  late String valorServicio;

  /// Polilíneas que representan la ruta.
  Set<Polyline> polylines = {};

  /// Indica si se está creando la solicitud.
  bool isSubmitting = false;

  /// Distancia aproximada de la ruta, en km (opcional, por si se quiere mostrar).
  double? routeDistanceKm;

  final MapService _mapService = const MapService();

  /// Calcula el valor del servicio según la hora
  void _calcularValorServicio() {
    final horaActual = DateTime.now();
    valorServicio = (horaActual.hour >= 18 || horaActual.hour < 6) ? '12000' : '10000';
  }

  Future<void> init() async {
    _calcularValorServicio();
    await _fetchRouteOSRM();
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
      final placemarks =
          await placemarkFromCoordinates(_center.latitude, _center.longitude);
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
    final parts = [name, street, subLocality, locality]
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return formatAddress(parts.take(2).join(', '));
  }

  /// Cambiar método de pago.
  void setMetodoPago(String value) {
    if (metodoPago == value) return;
    metodoPago = value;
    notifyListeners();
  }

  /// Bounds de cámara que abarcan origen, destino y la ruta.
  LatLngBounds? get cameraBounds {
    final points = <LatLng>[];
    points.add(origen.position);
    points.add(destino.position);
    for (final poly in polylines) {
      points.addAll(poly.points);
    }
    if (points.isEmpty) return null;
    return _mapService.computeBoundsFromPoints(points);
  }

  /// Llamada a OSRM para obtener la ruta detallada entre origen y destino.
  Future<void> _fetchRouteOSRM() async {
    final o = origen.position;
    final d = destino.position;
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${o.longitude},${o.latitude};${d.longitude},${d.latitude}?overview=full&geometries=geojson',
    );
    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        _buildDirectPolylineFallback();
        return;
      }
      final data = json.decode(resp.body) as Map<String, dynamic>?;
      if (data == null) {
        _buildDirectPolylineFallback();
        return;
      }
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _buildDirectPolylineFallback();
        return;
      }
      final route0 = routes[0] as Map<String, dynamic>;
      final geometry = route0['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['coordinates'] == null) {
        _buildDirectPolylineFallback();
        return;
      }
      final coords = geometry['coordinates'] as List;
      final points = coords.map<LatLng>((c) {
        // OSRM devuelve [lon, lat]
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      final newPolylines = <Polyline>{};
      newPolylines.add(_mapService.createPolyline(
        id: 'route',
        points: points,
        color: const Color(0xFFFAC001),
        width: 5,
        geodesic: true,
      ));
      polylines = newPolylines;

      final distance = (route0['distance'] is num)
          ? (route0['distance'] as num).toDouble()
          : null;
      if (distance != null) {
        routeDistanceKm = distance / 1000.0;
      } else {
        final dMeters = MapHelper.routeDistanceMeters(points);
        routeDistanceKm = dMeters / 1000.0;
      }

      notifyListeners();
    } on TimeoutException {
      _buildDirectPolylineFallback();
    } catch (_) {
      _buildDirectPolylineFallback();
    }
  }

  void _buildDirectPolylineFallback() {
    polylines = {
      _mapService.createPolyline(
        id: 'route',
        points: [origen.position, destino.position],
        color: const Color(0xFF448AFF),
        width: 5,
        geodesic: true,
      ),
    };
    notifyListeners();
  }

  /// Crea la solicitud en Firestore y devuelve el id generado,
  /// o null si hubo un error.
  Future<String?> crearSolicitud() async {
    if (isSubmitting) return null;
    isSubmitting = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      final clienteId = user?.uid;
      String? clienteNombre = user?.displayName;

      // Si no hay displayName, intentar leer el nombre canónico desde 'cliente'.
      if ((clienteNombre == null || clienteNombre.trim().isEmpty) &&
          clienteId != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('cliente')
              .doc(clienteId)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final dynamic maybeName = data != null ? data['nombre'] : null;
            if (maybeName is String && maybeName.trim().isNotEmpty) {
              clienteNombre = maybeName.trim();
            }
          }
        } catch (_) {
          // ignorar error de lectura y seguir con fallback
        }
      }

      // Fallback final: usar el email para derivar un nombre legible.
      if ((clienteNombre == null || clienteNombre.trim().isEmpty) &&
          user?.email != null) {
        final part = user!.email!.split('@').first;
        final formatted =
            part.replaceAll(RegExp(r'[._\-+]'), ' ');
        final words = formatted
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .map((w) {
          return w.length == 1
              ? w.toUpperCase()
              : '${w[0].toUpperCase()}${w.substring(1)}';
        }).join(' ');
        clienteNombre = words.isNotEmpty ? words : null;
      }

      final origenPos = origen.position;
      final origenAddress = origen.title;
      // intentar obtener foto de perfil del usuario (Auth) o desde doc 'cliente'
      String? clientePhotoUrl = user?.photoURL;
      if ((clientePhotoUrl == null || clientePhotoUrl.trim().isEmpty) && clienteId != null) {
        try {
          final doc = await FirebaseFirestore.instance.collection('cliente').doc(clienteId).get();
          if (doc.exists) {
            final data = doc.data();
            clientePhotoUrl = data != null
                ? (data['foto']?.toString() ?? data['fotoUrl']?.toString() ?? data['photo']?.toString() ?? data['photoUrl']?.toString())
                : null;
          }
        } catch (_) {}
      }

      final solicitud = {
        'cliente': {
          'id': clienteId,
          'nombre': clienteNombre ?? '',
          'foto': clientePhotoUrl ?? '',
          'ubicacion': {
            'lat': origenPos.latitude,
            'lng': origenPos.longitude,
            'address': origenAddress ?? '',
          },
        },
        'destino': {
          'title': destino.title ?? '',
          'lat': destino.position.latitude,
          'lng': destino.position.longitude,
        },
        'metodo_pago': metodoPago,
        'valor': valorServicio,
        'status': 'buscando',
        'creacion de solicitud': FieldValue.serverTimestamp(),
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
