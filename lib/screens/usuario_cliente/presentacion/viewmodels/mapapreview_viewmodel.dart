import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/direccion_format.dart';

/// Estado del mapa con pin centrado de "seleccionar destino" legacy
/// (`MapaPreviewView`, flujo "favorito casa"). El flujo con dos marcadores
/// (origen+destino, confirmar solicitud) vive ahora en
/// `caracteristicas/confirmar_solicitud/` — no lo repliques acá.
class MapapreviewViewModel extends ChangeNotifier {
  MapapreviewViewModel.forSelection({
    required LatLng initialLocation,
    String? initialDireccion,
    LatLng? origenLocation,
    String? origenDireccion,
  }) : _center = initialLocation,
       _initialDireccion = initialDireccion,
       _origenLocation = origenLocation,
       _origenDireccion = origenDireccion;

  /// Centro actual del mapa (coincide con la posición del indicador).
  LatLng _center;

  /// Dirección legible resuelta para el centro actual.
  String? _currentAddress;

  /// Dirección inicial pasada desde la pantalla anterior (si existe).
  final String? _initialDireccion;

  /// Información opcional sobre el origen, que puede usarse para etiquetas.
  final LatLng? _origenLocation;
  final String? _origenDireccion;

  LatLng get center => _center;

  String? get currentAddress => _currentAddress;

  String? get initialDireccion => _initialDireccion;

  LatLng? get origenLocation => _origenLocation;

  String? get origenDireccion => _origenDireccion;

  /// Actualiza el centro del mapa cuando la cámara se mueve.
  void updateCameraCenter(LatLng newCenter) {
    _center = newCenter;
    // No notificamos inmediatamente para no redibujar en cada frame de
    // movimiento. La vista se redibuja cuando termine el movimiento y se
    // resuelva la nueva dirección.
  }

  /// Resuelve una dirección legible para el centro actual del mapa.
  Future<void> reverseGeocodeCenter() async {
    try {
      final placemarks = await placemarkFromCoordinates(
        _center.latitude,
        _center.longitude,
      );
      if (placemarks.isNotEmpty) {
        final direccion = _buildFriendlyFromPlacemark(placemarks.first);
        _currentAddress = direccion.isNotEmpty ? direccion : null;
      } else {
        _currentAddress = null;
      }
    } catch (_) {
      _currentAddress = null;
    }
    notifyListeners();
  }

  /// Formatea una dirección para omitir el texto "Ocaña, Norte de
  /// Santander" y dejar solo las partes más relevantes.
  String formatAddress(String? address) => formatearDireccion(address);

  /// Construye una dirección amigable a partir de un Placemark.
  String _buildFriendlyFromPlacemark(Placemark p) {
    final name = p.name?.trim() ?? '';
    final street = p.street?.trim() ?? '';
    final subLocality = p.subLocality?.trim() ?? '';
    final locality = p.locality?.trim() ?? '';

    if (name.isNotEmpty && street.isNotEmpty) {
      return formatearDireccion('$name, $street');
    }
    if (street.isNotEmpty && locality.isNotEmpty) {
      return formatearDireccion('$street, $locality');
    }
    final parts = [
      name,
      street,
      subLocality,
      locality,
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return formatearDireccion(parts.take(2).join(', '));
  }
}
