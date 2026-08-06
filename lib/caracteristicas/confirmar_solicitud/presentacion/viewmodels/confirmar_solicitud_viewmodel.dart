import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/seleccion_destino/datos/repositorios/geocodificacion_repository_impl.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/casos_uso/obtener_direccion_desde_coordenadas_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../datos/repositorios/cliente_repository_impl.dart';
import '../../datos/repositorios/ruta_repository_impl.dart';
import '../../datos/repositorios/solicitud_repository_impl.dart';
import '../../dominio/casos_uso/calcular_tarifa_base_usecase.dart';
import '../../dominio/casos_uso/crear_solicitud_usecase.dart';
import '../../dominio/casos_uso/trazar_ruta_usecase.dart';
import '../../dominio/entidades/solicitud_borrador.dart';

/// Estado y orquestación de "Confirmar solicitud" (mapa con origen+destino,
/// tarifa, método de pago, comentario) — sin `BuildContext`. Mismo patrón de
/// DI que `SeleccionDestinoViewModel`: casos de uso opcionales con default a
/// implementaciones reales, porque esta pantalla se pushea directo y no
/// vive en el árbol de providers de `main.dart`.
///
/// A diferencia del `MapapreviewViewModel` legacy que este módulo reemplaza
/// para este flujo, `origen`/`destino` son mutables acá: ajustar cualquiera
/// de los dos actualiza el estado in-place y notifica, en vez de que la
/// vista tenga que destruir y recrear el ViewModel entero (con el rewiring
/// manual de listeners que eso implicaba) cada vez que el cliente movía un
/// pin.
class ConfirmarSolicitudViewModel extends ChangeNotifier {
  ConfirmarSolicitudViewModel({
    required LocationModel origenInicial,
    required LocationModel destinoInicial,
    CrearSolicitudUseCase? crearSolicitud,
    TrazarRutaUseCase? trazarRuta,
    CalcularTarifaBaseUseCase? calcularTarifaBase,
    ObtenerDireccionDesdeCoordenadasUseCase? obtenerDireccion,
  }) : _origen = origenInicial,
       _destino = destinoInicial,
       _crearSolicitudUseCase =
           crearSolicitud ??
           CrearSolicitudUseCase(
             solicitudRepository: SolicitudRepositoryImpl(),
             clienteRepository: ClienteRepositoryImpl(),
           ),
       _trazarRutaUseCase =
           trazarRuta ?? TrazarRutaUseCase(RutaRepositoryImpl()),
       _calcularTarifaBase =
           calcularTarifaBase ?? const CalcularTarifaBaseUseCase(),
       _obtenerDireccion =
           obtenerDireccion ??
           ObtenerDireccionDesdeCoordenadasUseCase(
             GeocodificacionRepositoryImpl(),
           ) {
    _valorServicio = _calcularTarifaBase(tipoVehiculo);
  }

  final CrearSolicitudUseCase _crearSolicitudUseCase;
  final TrazarRutaUseCase _trazarRutaUseCase;
  final CalcularTarifaBaseUseCase _calcularTarifaBase;
  final ObtenerDireccionDesdeCoordenadasUseCase _obtenerDireccion;

  /// Umbral de tiempo en background a partir del cual, al reanudar la app,
  /// se considera que la ubicación/ruta pudo quedar desactualizada y debe
  /// forzarse una recarga.
  static const Duration resumeReloadThreshold = Duration(seconds: 12);

  LocationModel _origen;
  LocationModel _destino;
  VehicleType tipoVehiculo = VehicleType.carro;
  late String _valorServicio;
  String metodoPago = 'Efectivo';
  String comentario = '';

  String? _direccionOrigen;
  bool _resolviendoDireccionOrigen = false;

  Set<Polyline> polylines = {};
  bool isLoadingRoute = false;
  double? routeDistanceKm;
  bool isSubmitting = false;

  // Descarta resultados de trazados de ruta obsoletos si origen/destino
  // cambian de nuevo antes de que el anterior termine.
  int _rutaToken = 0;

  LocationModel get origen => _origen;
  LocationModel get destino => _destino;
  String get valorServicio => _valorServicio;

  /// Dirección legible del origen para mostrar en la tarjeta "Tu ubicación
  /// actual" — `null` mientras se resuelve por primera vez.
  String? get direccionOrigen => _direccionOrigen;
  bool get resolviendoDireccionOrigen => _resolviendoDireccionOrigen;

  /// Valor sugerido para [tipo] con la distancia de la ruta ya trazada —
  /// para mostrar el precio de cada opción en el selector de vehículo sin
  /// que la vista tenga que reimplementar la fórmula de tarifa.
  String previsualizarValor(VehicleType tipo) {
    return _calcularTarifaBase(tipo, distanciaKm: routeDistanceKm);
  }

  /// Encuadre que contiene tanto el origen como el destino, para que la
  /// vista pueda encuadrar la cámara sin que el usuario tenga que mover el
  /// mapa con gestos.
  LatLngBounds get boundsOrigenDestino {
    final ori = _origen.position;
    final dest = _destino.position;
    return LatLngBounds(
      southwest: LatLng(
        math.min(ori.latitude, dest.latitude),
        math.min(ori.longitude, dest.longitude),
      ),
      northeast: LatLng(
        math.max(ori.latitude, dest.latitude),
        math.max(ori.longitude, dest.longitude),
      ),
    );
  }

  /// Indica si, dado el instante en que la app fue pausada y el instante
  /// actual, corresponde recargar el mapa/ruta al reanudar (regla de
  /// negocio pura, sin dependencia de `BuildContext`).
  bool shouldReloadOnResume(DateTime pausedAt, DateTime now) {
    return now.difference(pausedAt) >= resumeReloadThreshold;
  }

  Future<void> init() async {
    // Recalcula la tarifa en cada `init()` (incluido el resume desde
    // background) por si el horario diurno/nocturno cambió mientras la app
    // estaba en segundo plano — mismo criterio que el `MapapreviewViewModel`
    // legacy. `_recalcularRuta()` la vuelve a ajustar una vez se conozca la
    // distancia real (acá `routeDistanceKm` puede seguir siendo el de la
    // ruta anterior o `null`).
    _recalcularValor();
    await Future.wait([_resolverDireccionOrigenInicial(), _recalcularRuta()]);
  }

  /// Tarifa base del tipo de vehículo actual + costo por kilómetro de la
  /// ruta ya trazada (`routeDistanceKm`). Se llama cada vez que cambia el
  /// tipo de vehículo o la ruta (origen/destino ajustados), para que el
  /// valor sugerido siga la distancia real en vez de quedar fijo.
  void _recalcularValor() {
    _valorServicio = _calcularTarifaBase(
      tipoVehiculo,
      distanciaKm: routeDistanceKm,
    );
  }

  Future<void> _resolverDireccionOrigenInicial() async {
    final subtitle = _origen.subtitle?.trim();
    if (subtitle != null && subtitle.isNotEmpty) {
      _direccionOrigen = subtitle;
      notifyListeners();
      return;
    }
    _resolviendoDireccionOrigen = true;
    notifyListeners();
    final resuelta = await _obtenerDireccion(_origen.position);
    _direccionOrigen = resuelta;
    _resolviendoDireccionOrigen = false;
    notifyListeners();
  }

  /// Ajusta el origen (desde `SeleccionarUbicacionMapaView`) y recalcula la
  /// ruta. Si `direccionResuelta` viene vacío (el usuario confirmó sin que
  /// la vista alcanzara a resolver dirección), se geocodifica acá mismo.
  Future<void> actualizarOrigen(
    LatLng nuevaPosicion, {
    String? direccionResuelta,
  }) async {
    final direccion = await _resolverDireccionTexto(
      direccionResuelta,
      nuevaPosicion,
    );
    _origen = LocationModel(
      position: nuevaPosicion,
      title: direccion,
      subtitle: direccion,
    );
    _direccionOrigen = direccion;
    notifyListeners();
    unawaited(_recalcularRuta());
  }

  /// Ajusta el destino (desde `SeleccionarUbicacionMapaView`) y recalcula
  /// la ruta.
  Future<void> actualizarDestino(
    LatLng nuevaPosicion, {
    String? direccionResuelta,
  }) async {
    final direccion = await _resolverDireccionTexto(
      direccionResuelta,
      nuevaPosicion,
    );
    _destino = LocationModel(
      position: nuevaPosicion,
      title: direccion,
      subtitle: direccion,
    );
    notifyListeners();
    unawaited(_recalcularRuta());
  }

  Future<String> _resolverDireccionTexto(
    String? provista,
    LatLng posicion,
  ) async {
    final trimmed = provista?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return _obtenerDireccion(posicion);
  }

  Future<void> _recalcularRuta() async {
    final token = ++_rutaToken;
    isLoadingRoute = true;
    notifyListeners();

    final resultado = await _trazarRutaUseCase(
      _origen.position,
      _destino.position,
    );
    if (token != _rutaToken) return;

    polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: resultado.puntos,
        color: AppColores.primary,
        width: 5,
        geodesic: true,
      ),
    };
    routeDistanceKm = resultado.distanciaKm;
    isLoadingRoute = false;
    _recalcularValor();
    notifyListeners();
  }

  void setTipoVehiculo(VehicleType tipo) {
    if (tipoVehiculo == tipo) return;
    tipoVehiculo = tipo;
    _recalcularValor();
    notifyListeners();
  }

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

  /// Mínimo aceptable: la tarifa base del vehículo (sin el variable por km).
  /// Por debajo de eso ningún conductor tomaría el viaje, y ofertas de $1
  /// solo sirven para spamear a todos los conductores del radio.
  int get valorMinimoPermitido {
    final hora = DateTime.now().hour;
    final esNoche = hora >= 18 || hora < 6;
    return esNoche ? tipoVehiculo.basePriceNoche : tipoVehiculo.basePriceDia;
  }

  /// Techo anti fat-finger: 20× el valor sugerido. No busca acotar la
  /// negociación, solo evitar que un cero de más quede escrito en Firestore.
  int get valorMaximoPermitido {
    final sugerido = int.tryParse(previsualizarValor(tipoVehiculo)) ?? 10000;
    return sugerido * 20;
  }

  /// `null` si [digits] es un valor aceptable; si no, el motivo para mostrar
  /// en la UI. Antes no había ningún límite en toda la cadena: `1` y
  /// `999999999999` se escribían igual en el documento.
  String? validarValorServicio(String digits) {
    final valor = int.tryParse(digits.replaceAll(RegExp(r'[^0-9]'), ''));
    if (valor == null || valor <= 0) return 'Ingresa un valor válido.';
    if (valor < valorMinimoPermitido) {
      return 'El valor mínimo para ${tipoVehiculo.label.toLowerCase()} es '
          '\$${_formatMiles(valorMinimoPermitido)}.';
    }
    if (valor > valorMaximoPermitido) {
      return 'El valor máximo es \$${_formatMiles(valorMaximoPermitido)}.';
    }
    return null;
  }

  static String _formatMiles(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final rev = s.length - i;
      buf.write(s[i]);
      if (rev > 1 && rev % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }

  void setValorServicio(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;

    final normalized = int.tryParse(digits)?.toString();
    if (normalized == null || normalized.isEmpty) return;
    if (_valorServicio == normalized) return;

    _valorServicio = normalized;
    notifyListeners();
  }

  /// Crea la solicitud y devuelve su id, o `null` si hubo un error.
  Future<String?> crearSolicitud() async {
    if (isSubmitting) return null;
    isSubmitting = true;
    notifyListeners();

    try {
      final borrador = SolicitudBorrador(
        origen: _origen,
        destino: _destino,
        tipoVehiculo: tipoVehiculo,
        metodoPago: metodoPago,
        comentario: comentario,
        valorServicio: _valorServicio,
      );
      return await _crearSolicitudUseCase(borrador);
    } catch (_) {
      return null;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}
