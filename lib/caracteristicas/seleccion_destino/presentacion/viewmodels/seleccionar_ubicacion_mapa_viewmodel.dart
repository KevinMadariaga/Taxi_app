import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../datos/repositorios/geocodificacion_repository_impl.dart';
import '../../dominio/casos_uso/obtener_direccion_desde_coordenadas_usecase.dart';
import '../../dominio/entidades/seleccion_ubicacion_result.dart';

/// Estado y orquestación de "seleccionar ubicación en el mapa" — sin
/// `BuildContext`. Mismo patrón que `SeleccionDestinoViewModel`: caso de uso
/// opcional con default a la implementación real, porque esta vista se
/// pushea directo y no vive en el árbol de providers de `main.dart`.
class SeleccionarUbicacionMapaViewModel extends ChangeNotifier {
  SeleccionarUbicacionMapaViewModel({
    required LatLng ubicacionInicial,
    String? direccionInicial,
    ObtenerDireccionDesdeCoordenadasUseCase? obtenerDireccion,
  }) : _obtenerDireccion =
           obtenerDireccion ??
           ObtenerDireccionDesdeCoordenadasUseCase(
             GeocodificacionRepositoryImpl(),
           ),
       _center = ubicacionInicial {
    final inicial = direccionInicial?.trim() ?? '';
    if (inicial.isNotEmpty) {
      _direccion = inicial;
      _direccionCache[_keyDe(_center)] = inicial;
    } else {
      unawaited(_actualizarDireccion(_center));
    }
  }

  static const _umbralMovimiento = 0.00005;
  static const _debounceIdle = Duration(milliseconds: 180);

  final ObtenerDireccionDesdeCoordenadasUseCase _obtenerDireccion;
  final Map<String, String> _direccionCache = <String, String>{};

  LatLng _center;
  String _direccion = '';
  bool _resolviendoDireccion = false;
  bool _contenidoVisible = false;
  int _requestToken = 0;
  Timer? _idleDebounce;
  LatLng? _ultimaCoordConsultada;

  LatLng get center => _center;
  String get direccion => _direccion;
  bool get resolviendoDireccion => _resolviendoDireccion;
  bool get contenidoVisible => _contenidoVisible;

  /// Dispara la animación de entrada del panel inferior. Se llama después
  /// del primer frame para que la transición de entrada de la ruta no
  /// compita con ella.
  void mostrarContenido() {
    if (_contenidoVisible) return;
    _contenidoVisible = true;
    notifyListeners();
  }

  void onCameraMove(CameraPosition position) {
    _center = position.target;
  }

  void onCameraIdle() {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(_debounceIdle, () {
      final ultima = _ultimaCoordConsultada;
      if (ultima != null && !_seMovioLoSuficiente(ultima, _center)) return;
      _ultimaCoordConsultada = _center;
      unawaited(_actualizarDireccion(_center));
    });
  }

  SeleccionUbicacionResult confirmar() {
    return SeleccionUbicacionResult(position: _center, direccion: _direccion);
  }

  String _keyDe(LatLng coordenada) {
    return '${coordenada.latitude.toStringAsFixed(5)},'
        '${coordenada.longitude.toStringAsFixed(5)}';
  }

  bool _seMovioLoSuficiente(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() > _umbralMovimiento ||
        (a.longitude - b.longitude).abs() > _umbralMovimiento;
  }

  Future<void> _actualizarDireccion(LatLng coordenada) async {
    final key = _keyDe(coordenada);
    final cacheada = _direccionCache[key];
    if (cacheada != null && cacheada.isNotEmpty) {
      if (_direccion == cacheada && !_resolviendoDireccion) return;
      _direccion = cacheada;
      _resolviendoDireccion = false;
      notifyListeners();
      return;
    }

    final token = ++_requestToken;
    if (!_resolviendoDireccion) {
      _resolviendoDireccion = true;
      notifyListeners();
    }

    final resuelta = await _obtenerDireccion(coordenada);
    if (token != _requestToken) return;

    _direccionCache[key] = resuelta;
    _direccion = resuelta;
    _resolviendoDireccion = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    super.dispose();
  }
}
