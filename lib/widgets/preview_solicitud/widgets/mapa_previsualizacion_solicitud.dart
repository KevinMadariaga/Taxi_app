import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/app_remote_config_service.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

/// Mitad superior de la tarjeta de previsualización: imagen estática de
/// Google Static Maps con la perspectiva "del conductor hacia el cliente" —
/// encuadra ambos puntos (no rota/inclina la cámara: Static Maps siempre es
/// norte-arriba, la "perspectiva" acá es el encuadre que conecta ambos
/// puntos, igual criterio que usa `_BuscandoTaxiStaticMap` del lado
/// cliente) y overlayea los íconos propios de la app sobre la imagen:
/// vehículo del conductor (carro/moto) y el pin de marca (`map_pin_red.png`)
/// sobre la ubicación del cliente — Static Maps no puede referenciar un
/// asset local en su parámetro `markers=`, así que los íconos se dibujan
/// encima calculando su offset en píxeles vía [ProyeccionMercator].
class MapaPrevisualizacionSolicitud extends StatelessWidget {
  const MapaPrevisualizacionSolicitud({
    super.key,
    required this.driverLocation,
    required this.clientLocation,
    this.isMoto = false,
    this.routePoints = const [],
    this.isLoadingRoute = false,
    this.heading,
    this.orientarHaciaCliente = false,
  });

  final LatLng? driverLocation;
  final LatLng clientLocation;
  final bool isMoto;

  /// Puntos de la ruta real (OSRM) entre conductor y cliente, si ya se
  /// resolvió — dibuja la trazabilidad entre los dos marcadores en vez de
  /// dejarlos sueltos. Vacía mientras se está calculando o si falló.
  final List<LatLng> routePoints;

  /// Rumbo (grados, 0 = norte, sentido horario) hacia donde apunta el
  /// ícono del vehículo — viene ya calculado del viewmodel siguiendo la
  /// ruta real (calle a calle) hacia el cliente, no la línea recta entre
  /// ambos puntos. `null` cae al rumbo en línea recta conductor→cliente
  /// (caso de la preview antes de aceptar, sin ruta OSRM todavía resuelta).
  final double? heading;

  /// `true` mientras se resuelve la ruta OSRM — bloquea el pedido de la
  /// imagen estática hasta que se resuelva (con o sin traza). Sin esto, el
  /// mapa pedía la imagen sin `path` apenas se abría la preview y volvía a
  /// pedirla con `path` en cuanto llegaba la ruta: dos requests y un
  /// crossfade visible en vez de cargar una sola vez ya con la traza.
  final bool isLoadingRoute;

  /// Rota el mapa completo para que el rumbo conductor→cliente quede
  /// apuntando hacia ARRIBA: el conductor queda abajo y el cliente arriba,
  /// como la brújula de un navegador, en vez del norte-arriba que devuelve
  /// Static Maps (donde el conductor aparecía arriba o abajo según la
  /// geografía). La imagen se pide cuadrada y del tamaño de la diagonal del
  /// recuadro para que al rotarla no queden esquinas vacías.
  ///
  /// Solo lo usa el viaje del conductor. La preview previa a aceptar sigue
  /// norte-arriba (`false`), donde lo que importa es ubicarse, no seguir un
  /// rumbo.
  final bool orientarHaciaCliente;

  static const adapter.MapService _mapService = adapter.MapService();

  /// Máximo del parámetro `size` de Static Maps (por dimensión, antes de
  /// aplicar `scale`).
  static const double _ladoMaximoStaticMaps = 640;

  static const double _vehicleIconSize = 40;
  static const double _pinIconSize = 44;
  static const double _zoomSinConductor = 16;

  // Fracción del segmento conductor→cliente donde cae el centro del
  // encuadre: 0.5 sería el punto medio exacto (simétrico). Un valor menor
  // deja al conductor más cerca del centro y más margen del lado del
  // cliente — la aproximación más cercana a "perspectiva del conductor
  // hacia el cliente" que admite una imagen estática (Static Maps no puede
  // rotar/inclinar la cámara como sí hace el mapa en vivo). Se mantiene
  // cerca de 0.5 a propósito: `boundsZoom` calcula el zoom asumiendo
  // encuadre simétrico, así que descentrar de más arriesga sacar el pin
  // más lejano fuera del cuadro.
  static const double _fraccionCentro = 0.45;

  // Con el mapa orientado al rumbo, el centro se corre HACIA el cliente: el
  // conductor baja en pantalla y queda más recorrido a la vista por delante
  // de él, que es el punto de orientar la vista al rumbo.
  static const double _fraccionCentroOrientado = 0.58;

  // Márgenes más chicos que el default de `boundsZoom` (90/120): esta
  // tarjeta es más angosta que el mapa de "buscando taxi", así que un
  // margen tan grande dejaba los dos puntos chicos y separados del borde —
  // se ve más "alejado" de lo que pidió el conductor.
  static const double _margenHorizontal = 56.0;
  static const double _margenVertical = 72.0;

  @override
  Widget build(BuildContext context) {
    if (isLoadingRoute) {
      return const _MapaPreviewCargando();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final driver = driverLocation;

        // Static Maps API acepta como máximo 640x640 en "size" (antes de
        // aplicar "scale") — mismo límite que ya respetan los demás mapas
        // estáticos de la app.
        final double width = constraints.maxWidth.clamp(100.0, 640.0);
        final double height = constraints.maxHeight.clamp(100.0, 640.0);

        final bool hasDriver = driver != null;
        final bool rotar = orientarHaciaCliente && hasDriver;

        // Rotado, la imagen tiene que ser cuadrada y cubrir la diagonal del
        // recuadro: es el único tamaño que, gire lo que gire, sigue tapando
        // las cuatro esquinas. Si esa diagonal pasa el máximo de Static Maps
        // se pide el máximo y se amplía por `factorEscala` — con `scale=2` la
        // imagen trae el doble de píxeles reales, así que ampliar un poco no
        // se ve pixelado.
        final double diagonal = math.sqrt(width * width + height * height);
        final double ladoPedido = rotar
            ? math.min(diagonal, _ladoMaximoStaticMaps)
            : 0;
        final double factorEscala = rotar ? diagonal / ladoPedido : 1;

        final double rotacionRad = rotar
            ? ProyeccionMercator.rotacionParaRumboArriba(
                ProyeccionMercator.bearingDegrees(driver, clientLocation),
              )
            : 0;
        final double fraccion = rotar
            ? _fraccionCentroOrientado
            : _fraccionCentro;
        final LatLng center = hasDriver
            ? LatLng(
                driver.latitude +
                    (clientLocation.latitude - driver.latitude) * fraccion,
                driver.longitude +
                    (clientLocation.longitude - driver.longitude) * fraccion,
              )
            : clientLocation;

        // Redondeado ACÁ, una sola vez: Static Maps solo acepta zoom
        // entero, así que la imagen real siempre se renderiza al valor
        // truncado. Si los offsets de los íconos se calculan con el zoom
        // sin truncar, la matemática de posición asume una imagen más
        // acercada de la que realmente llegó y los íconos quedan
        // desplazados del punto real.
        final double zoom =
            (rotar
                    // Rotado se mide sobre la ruta completa, no solo sobre los
                    // dos extremos: la traza se curva y con el encuadre de dos
                    // puntos se salía del recuadro por el costado.
                    ? ProyeccionMercator.boundsZoomRotado(
                        [driver, ...routePoints, clientLocation],
                        center: center,
                        rotacionRad: rotacionRad,
                        // Divididos por `factorEscala` porque estas cuentas
                        // están en píxeles de la imagen, y la imagen se dibuja
                        // ampliada por ese factor.
                        widthPx: width / factorEscala,
                        heightPx: height / factorEscala,
                        margenHorizontal: _margenHorizontal / factorEscala,
                        margenVertical: _margenVertical / factorEscala,
                      )
                    : hasDriver
                    ? ProyeccionMercator.boundsZoom(
                        driver,
                        clientLocation,
                        width,
                        height,
                        margenHorizontal: _margenHorizontal,
                        margenVertical: _margenVertical,
                      )
                    : _zoomSinConductor)
                .floorToDouble();

        return FutureBuilder<String>(
          future: AppRemoteConfigService.instance.fetchStaticMapsApiKey(),
          builder: (context, keySnapshot) {
            if (keySnapshot.connectionState != ConnectionState.done) {
              return const _MapaPreviewCargando();
            }
            final apiKey = keySnapshot.data ?? '';
            if (apiKey.isEmpty) {
              return const _MapaPreviewPlaceholder();
            }

            // El routing (OSRM) "engancha" la ruta al punto ruteable más
            // cercano, que casi nunca es exactamente la coordenada del
            // conductor/cliente — sin esto la línea queda flotando a un
            // tramo de los íconos en vez de salir/llegar justo desde/hacia
            // ellos. Se antepone/agrega la coordenada exacta como primer y
            // último punto para que la traza siempre los toque.
            final String? encodedPath = routePoints.length >= 2
                ? _mapService.encodePolyline([
                    if (hasDriver) driver,
                    ...routePoints,
                    clientLocation,
                  ])
                : null;

            // Rotado el lienzo es el cuadrado de la diagonal; sin rotar, el
            // recuadro tal cual.
            final double lienzoAncho = rotar ? ladoPedido : width;
            final double lienzoAlto = rotar ? ladoPedido : height;

            final url = _staticMapUrl(
              center: center,
              zoom: zoom,
              width: lienzoAncho.round(),
              height: lienzoAlto.round(),
              apiKey: apiKey,
              encodedPath: encodedPath,
            );

            final mapa = Stack(
              fit: StackFit.expand,
              children: [
                // Sin `key: ValueKey(url)`: cuando la ruta OSRM llega y
                // `encodedPath` pasa de null a un valor, `url` cambia — con
                // una key atada a esa url, Flutter trata el cambio como un
                // widget nuevo y vuelve a mostrar el `placeholder` (spinner)
                // en vez de una transición suave. Sin key, es el MISMO
                // `CachedNetworkImage` actualizando su `imageUrl`, así que
                // usa su propio crossfade interno entre la imagen vieja y
                // la nueva.
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  // Sin esto, `useOldImageOnUrlChange` por defecto es `false`
                  // y cada cambio de `url` (cada pocos segundos, con cada GPS
                  // ping del conductor) limpiaba la imagen y mostraba el
                  // placeholder (spinner) de nuevo — el parpadeo periódico
                  // reportado en QA, no relacionado con `_vm.isLoading`.
                  useOldImageOnUrlChange: true,
                  placeholder: (context, _) => const _MapaPreviewCargando(),
                  errorWidget: (context, _, error) {
                    ErrorReporter.report(
                      error,
                      StackTrace.current,
                      reason:
                          'mapa_previsualizacion_solicitud: falló imagen de Static Maps',
                    );
                    return const _MapaPreviewPlaceholder();
                  },
                ),
                _MapaPinOverlay(
                  offset: ProyeccionMercator.pixelOffset(
                    center: center,
                    point: clientLocation,
                    zoom: zoom,
                  ),
                  boxWidth: lienzoAncho,
                  boxHeight: lienzoAlto,
                  iconSize: _pinIconSize,
                  // El pin es una gota que apunta a su punto: tiene que
                  // quedar vertical en PANTALLA, así que se contrarrota lo
                  // que se rotó el lienzo. El vehículo no: ese sí gira con el
                  // mapa, porque su rumbo es relativo al terreno.
                  child: Transform.rotate(
                    angle: -rotacionRad,
                    child: Image.asset(
                      'assets/img/map_pin_red.png',
                      width: _pinIconSize,
                      height: _pinIconSize,
                    ),
                  ),
                ),
                if (hasDriver)
                  _MapaPinOverlay(
                    offset: ProyeccionMercator.pixelOffset(
                      center: center,
                      point: driver,
                      zoom: zoom,
                    ),
                    boxWidth: lienzoAncho,
                    boxHeight: lienzoAlto,
                    iconSize: _vehicleIconSize,
                    anchorBottom: false,
                    child: Transform.rotate(
                      angle:
                          (heading ??
                              ProyeccionMercator.bearingDegrees(
                                driver,
                                clientLocation,
                              )) *
                          (math.pi / 180),
                      child: Image.asset(
                        isMoto
                            ? 'assets/img/icono_moto.png'
                            : 'assets/img/icono_carro.png',
                        width: _vehicleIconSize,
                        height: _vehicleIconSize,
                      ),
                    ),
                  ),
              ],
            );

            if (!rotar) return mapa;

            // El lienzo cuadrado excede el recuadro, así que necesita
            // `OverflowBox` para poder pintarse más grande que sus
            // constraints, y `ClipRect` para no derramarse sobre la tarjeta.
            return ClipRect(
              child: OverflowBox(
                maxWidth: diagonal,
                maxHeight: diagonal,
                child: Transform.rotate(
                  angle: rotacionRad,
                  child: Transform.scale(
                    scale: factorEscala,
                    child: SizedBox(
                      width: ladoPedido,
                      height: ladoPedido,
                      child: mapa,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _staticMapUrl({
    required LatLng center,
    required double zoom,
    required int width,
    required int height,
    required String apiKey,
    String? encodedPath,
  }) {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom.floor().toString(),
      'size': '${width}x$height',
      'scale': '2',
      'maptype': 'roadmap',
      'key': apiKey,
      // Static Maps espera RRGGBBAA (hex, sin '#', alpha al final) — se
      // arma desde `AppColores.primary` (naranja de marca) en vez de un
      // hex suelto para no volver a desincronizarse si el color cambia.
      if (encodedPath != null)
        'path': 'color:0x${_routePathHex()}|weight:5|enc:$encodedPath',
    });
    return uri.toString();
  }

  /// `RRGGBBAA` (Static Maps) desde `AppColores.primary` con ~80% opacidad
  /// — el `Color` de Flutter guarda alpha primero (`AARRGGBB`).
  String _routePathHex() {
    final rgb = (AppColores.primary.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '${rgb}CC';
  }
}

/// Posiciona un ícono exacto sobre un punto del mapa, dado su [offset] en
/// píxeles respecto al centro de la imagen.
///
/// [anchorBottom] controla qué parte del ícono cae sobre el punto:
/// - `true` (pin/gota, `map_pin_red.png`): la PUNTA, borde inferior central
///   del asset.
/// - `false` (vista cenital, `icono_carro.png`/`icono_moto.png`): el CENTRO
///   del asset, porque ahí está el vehículo en un ícono visto desde arriba.
class _MapaPinOverlay extends StatelessWidget {
  const _MapaPinOverlay({
    required this.offset,
    required this.boxWidth,
    required this.boxHeight,
    required this.iconSize,
    required this.child,
    this.anchorBottom = true,
  });

  final Offset offset;
  final double boxWidth;
  final double boxHeight;
  final double iconSize;
  final Widget child;
  final bool anchorBottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: boxWidth / 2 + offset.dx - iconSize / 2,
      top: boxHeight / 2 + offset.dy - (anchorBottom ? iconSize : iconSize / 2),
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
}

class _MapaPreviewPlaceholder extends StatelessWidget {
  const _MapaPreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColores.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(
        Icons.map_outlined,
        size: 40,
        color: AppColores.textSecondary.withValues(alpha: 0.6),
      ),
    );
  }
}

class _MapaPreviewCargando extends StatelessWidget {
  const _MapaPreviewCargando();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColores.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
