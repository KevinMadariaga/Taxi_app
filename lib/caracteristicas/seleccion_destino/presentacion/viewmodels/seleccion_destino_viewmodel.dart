import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/utils/error_reporter.dart';

import '../../datos/repositorios/historial_destinos_repository_impl.dart';
import '../../datos/repositorios/lugares_repository_impl.dart';
import '../../datos/repositorios/ubicaciones_repository_impl.dart';
import '../../dominio/entidades/ubicacion_entity.dart';
import '../../dominio/casos_uso/buscar_destinos_usecase.dart';
import '../../dominio/casos_uso/extraer_ubicacion_desde_texto_usecase.dart';
import '../../dominio/casos_uso/guardar_favorito_usecase.dart';
import '../../dominio/casos_uso/obtener_favoritos_usecase.dart';
import '../../dominio/casos_uso/obtener_historial_destinos_usecase.dart';
import '../../dominio/casos_uso/registrar_destino_reciente_usecase.dart';
import '../../dominio/casos_uso/resolver_detalle_lugar_usecase.dart';

/// Estado y orquestación de la pantalla de selección de destino — sin
/// `BuildContext`. Wiring local: los casos de uso son opcionales con default
/// a implementaciones reales (mismo patrón que `HomeAuthController`), porque
/// esta pantalla se pushea directo y no vive en el árbol de providers de
/// `main.dart`.
class SeleccionDestinoViewModel extends ChangeNotifier {
  SeleccionDestinoViewModel({
    BuscarDestinosUseCase? buscarDestinos,
    GuardarFavoritoUseCase? guardarFavorito,
    ObtenerFavoritosUseCase? obtenerFavoritos,
    ResolverDetalleLugarUseCase? resolverDetalleLugar,
    ExtraerUbicacionDesdeTextoUseCase? extraerUbicacionDesdeTexto,
    ObtenerHistorialDestinosUseCase? obtenerHistorialDestinos,
    RegistrarDestinoRecienteUseCase? registrarDestinoReciente,
  }) : _buscarDestinos =
           buscarDestinos ??
           BuscarDestinosUseCase(
             UbicacionesRepositoryImpl(),
             LugaresRepositoryImpl(),
           ),
       _guardarFavoritoUseCase =
           guardarFavorito ??
           GuardarFavoritoUseCase(UbicacionesRepositoryImpl()),
       _obtenerFavoritosUseCase =
           obtenerFavoritos ??
           ObtenerFavoritosUseCase(UbicacionesRepositoryImpl()),
       _resolverDetalleLugar =
           resolverDetalleLugar ??
           ResolverDetalleLugarUseCase(LugaresRepositoryImpl()),
       _extraerUbicacionDesdeTexto =
           extraerUbicacionDesdeTexto ??
           const ExtraerUbicacionDesdeTextoUseCase(),
       _obtenerHistorialDestinos =
           obtenerHistorialDestinos ??
           ObtenerHistorialDestinosUseCase(HistorialDestinosRepositoryImpl()),
       _registrarDestinoReciente =
           registrarDestinoReciente ??
           RegistrarDestinoRecienteUseCase(HistorialDestinosRepositoryImpl());

  final BuscarDestinosUseCase _buscarDestinos;
  final GuardarFavoritoUseCase _guardarFavoritoUseCase;
  final ObtenerFavoritosUseCase _obtenerFavoritosUseCase;
  final ResolverDetalleLugarUseCase _resolverDetalleLugar;
  final ExtraerUbicacionDesdeTextoUseCase _extraerUbicacionDesdeTexto;
  final ObtenerHistorialDestinosUseCase _obtenerHistorialDestinos;
  final RegistrarDestinoRecienteUseCase _registrarDestinoReciente;

  final Map<String, String> _direccionCache = <String, String>{};

  LatLng? _origenPosition;
  String _origenDireccion = '';
  LatLng? _destinoPosition;
  String _destinoDireccion = '';

  List<UbicacionEntity> _sugerencias = [];
  List<UbicacionEntity> _favoritos = [];
  List<UbicacionEntity> _historial = [];

  bool _cargandoSugerencias = false;
  bool _cargandoFavoritos = false;
  bool _guardandoFavorito = false;
  bool _cargandoHistorial = false;
  String? _error;

  LatLng? get origenPosition => _origenPosition;
  String get origenDireccion => _origenDireccion;
  LatLng? get destinoPosition => _destinoPosition;
  String get destinoDireccion => _destinoDireccion;
  List<UbicacionEntity> get sugerencias => _sugerencias;
  List<UbicacionEntity> get favoritos => _favoritos;
  List<UbicacionEntity> get historial => _historial;
  bool get cargandoSugerencias => _cargandoSugerencias;
  bool get cargandoFavoritos => _cargandoFavoritos;
  bool get guardandoFavorito => _guardandoFavorito;
  bool get cargandoHistorial => _cargandoHistorial;
  String? get error => _error;
  bool get tieneDestino => _destinoPosition != null;

  String _keyFromLatLng(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  }

  String coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  /// En Colombia `street` suele venir ya con el número incluido (ej.
  /// "Cra. 10ª # 20-10"), pero algunos dispositivos además devuelven ese
  /// mismo número suelto en otro campo (ej. "# 20-10") — sin deduplicar se ve
  /// repetido ("# 20-10, Cra. 10ª # 20-10"). Se descarta cualquier parte que
  /// ya esté contenida en otra (se queda con la más completa).
  String _direccionAmigable(Placemark p, LatLng fallback) {
    final partes = [
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
    ].map((s) => (s ?? '').trim()).where((s) => s.isNotEmpty).toList();

    final unicas = <String>[];
    for (final parte in partes) {
      final parteLower = parte.toLowerCase();
      if (unicas.any((u) => u.toLowerCase().contains(parteLower))) continue;
      unicas.removeWhere((u) => parteLower.contains(u.toLowerCase()));
      unicas.add(parte);
    }

    final direccion = unicas.join(', ');
    if (direccion.trim().isEmpty) return coordsText(fallback);
    return direccion;
  }

  /// Resuelve (con caché en memoria por coordenada) la dirección amigable de
  /// un punto vía geocoding inverso — usado tanto para el origen como para
  /// cualquier punto elegido en el mapa (favorito, destino, ubicación pegada).
  Future<String> resolverDireccion(LatLng punto) async {
    final key = _keyFromLatLng(punto);
    final cached = _direccionCache[key];
    if (cached != null && cached.trim().isNotEmpty) return cached;

    try {
      final placemarks = await placemarkFromCoordinates(
        punto.latitude,
        punto.longitude,
      );
      if (placemarks.isNotEmpty) {
        final resuelta = _direccionAmigable(placemarks.first, punto);
        _direccionCache[key] = resuelta;
        return resuelta;
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
    }
    final fallback = coordsText(punto);
    _direccionCache[key] = fallback;
    return fallback;
  }

  /// Inicializa el origen: usa la dirección ya conocida (resuelta antes de
  /// entrar a esta pantalla) si vino, o geocodifica `posicionInicial`.
  Future<void> init({LatLng? posicionInicial, String? direccionInicial}) async {
    _origenPosition = posicionInicial;
    final direccion = direccionInicial?.trim() ?? '';
    if (direccion.isNotEmpty) {
      _origenDireccion = direccion;
    } else if (posicionInicial != null) {
      _origenDireccion = await resolverDireccion(posicionInicial);
    }
    notifyListeners();
  }

  Future<void> actualizarOrigen(LatLng posicion, {String? direccion}) async {
    _origenPosition = posicion;
    _origenDireccion = direccion?.trim().isNotEmpty == true
        ? direccion!.trim()
        : await resolverDireccion(posicion);
    notifyListeners();
  }

  void actualizarDestino(LatLng posicion, String direccion) {
    _destinoPosition = posicion;
    _destinoDireccion = direccion;
    _sugerencias = [];
    notifyListeners();
  }

  void limpiarDestino() {
    _destinoPosition = null;
    _destinoDireccion = '';
    notifyListeners();
  }

  Future<void> buscarSugerencias(String query) async {
    if (query.trim().isEmpty) {
      _sugerencias = [];
      notifyListeners();
      return;
    }
    _cargandoSugerencias = true;
    notifyListeners();
    try {
      _sugerencias = await _buscarDestinos(query);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
      _sugerencias = [];
    } finally {
      _cargandoSugerencias = false;
      notifyListeners();
    }
  }

  /// Resuelve el detalle (coordenadas) de una sugerencia de Places que solo
  /// trae `placeId`. Devuelve `null` si falla.
  Future<UbicacionEntity?> resolverDetalleLugar(String placeId) {
    return _resolverDetalleLugar(placeId);
  }

  Future<void> cargarFavoritos({String tipo = 'Favorito'}) async {
    _cargandoFavoritos = true;
    notifyListeners();
    try {
      _favoritos = await _obtenerFavoritosUseCase(tipo: tipo);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
      _favoritos = [];
    } finally {
      _cargandoFavoritos = false;
      notifyListeners();
    }
  }

  Future<bool> guardarFavorito({
    required String nombre,
    required LatLng ubicacion,
    required String direccion,
    String tipo = 'Favorito',
  }) async {
    _guardandoFavorito = true;
    _error = null;
    notifyListeners();
    try {
      await _guardarFavoritoUseCase(
        nombre: nombre,
        direccion: direccion,
        ubicacion: ubicacion,
        tipo: tipo,
      );
      return true;
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
      _error = 'No se pudo guardar la ubicación.';
      return false;
    } finally {
      _guardandoFavorito = false;
      notifyListeners();
    }
  }

  Future<LatLng?> extraerUbicacionDesdeTexto(String text) {
    return _extraerUbicacionDesdeTexto(text);
  }

  /// Carga el historial de destinos recientes — a diferencia de favoritos
  /// (que se cargan al abrir su modal), esto se llama al entrar a la
  /// pantalla porque el historial se muestra directo en el cuerpo, no
  /// detrás de una acción explícita.
  Future<void> cargarHistorial() async {
    _cargandoHistorial = true;
    notifyListeners();
    try {
      _historial = await _obtenerHistorialDestinos();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
      _historial = [];
    } finally {
      _cargandoHistorial = false;
      notifyListeners();
    }
  }

  /// Registra el destino ya confirmado como el más reciente del historial.
  /// No bloquea ni notifica error al usuario si falla — es una comodidad de
  /// UX, no algo que deba interrumpir el flujo de confirmar un destino.
  Future<void> registrarDestinoReciente({
    required String nombre,
    required String direccion,
    required LatLng posicion,
  }) async {
    try {
      await _registrarDestinoReciente(
        UbicacionEntity(
          nombre: nombre,
          direccion: direccion,
          position: posicion,
          tipo: 'reciente',
        ),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoViewModel');
    }
  }
}
