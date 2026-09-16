import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/map_style.dart';
import 'package:taxi_app/core/services/app_remote_config_service.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

/// Mitad superior de la tarjeta de previsualización: imagen estática de
/// Google Static Maps con la perspectiva "del conductor hacia el cliente" —
/// encuadra los puntos disponibles (no rota/inclina la cámara: Static Maps
/// siempre es norte-arriba, la "perspectiva" acá es el encuadre que conecta
/// los puntos, igual criterio que usa `_BuscandoTaxiStaticMap` del lado
/// cliente) y overlayea los íconos propios de la app sobre la imagen:
/// vehículo del conductor (carro/moto), un badge con ícono de persona sobre
/// la ubicación del cliente y, si se conoce el destino del viaje, un badge
/// de bandera sobre ese punto — Static Maps no puede referenciar un
/// asset local en su parámetro `markers=`, así que los íconos se dibujan
/// encima calculando su offset en píxeles vía [ProyeccionMercator].
///
/// Con [destinoLocation], además del tramo conductor→cliente (naranja de
/// marca, `AppColores.primary`) se traza el tramo cliente→destino en el
/// mismo naranja pero más claro (`AppColores.brand200`) — misma familia de
/// color para que se lea como "un solo viaje", diferenciable por
/// intensidad en vez de un color ajeno (antes azul informativo) — para que
/// el conductor vea el viaje completo antes de aceptar: no solo a dónde
/// recoger, también a dónde va a dejar al cliente. El encuadre pasa a
/// cubrir TODOS los puntos (recogida + viaje),
/// vía [ProyeccionMercator.centroRotado] en vez de la heurística de
/// [_fraccionCentro]/[_fraccionCentroOrientado] (pensada para dos puntos
/// simétricos, no para un recorrido completo).
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
    this.destinoLocation,
    this.routeDestinoPoints = const [],
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
  /// Lo usan tanto el viaje ya en curso como la preview previa a aceptar.
  /// Sin efecto mientras no hay `driverLocation` (sin conductor no hay
  /// rumbo que trazar, el mapa queda norte-arriba centrado en el cliente).
  final bool orientarHaciaCliente;

  /// Destino final del viaje (a dónde el conductor debe dejar al cliente
  /// después de recogerlo) — `null` en los casos que no lo conocen o no lo
  /// necesitan (viaje ya en curso, cuando este mismo widget se reutiliza
  /// solo para la traza conductor→objetivo actual).
  final LatLng? destinoLocation;

  /// Ruta real (OSRM) cliente→destino, si ya se resolvió — mismo criterio
  /// que [routePoints] pero para el segundo tramo del viaje. Vacía mientras
  /// se calcula, si falló, o si `destinoLocation` es `null`.
  final List<LatLng> routeDestinoPoints;

  static const adapter.MapService _mapService = adapter.MapService();

  /// Máximo del parámetro `size` de Static Maps (por dimensión, antes de
  /// aplicar `scale`).
  static const double _ladoMaximoStaticMaps = 640;

  static const double _vehicleIconSize = 40;
  static const double _clienteIconSize = 40;
  static const double _destinoIconSize = 32;
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
        final LatLng? destino = destinoLocation;
        // Con destino conocido el encuadre deja de ser el segmento
        // conductor→cliente para cubrir el viaje completo — el centro del
        // bbox de todos los puntos es el único que encuadra todo al mayor
        // zoom posible (ver docstring de [ProyeccionMercator.centroRotado]).
        final LatLng center = destino != null
            ? ProyeccionMercator.centroRotado([
                if (hasDriver) driver,
                ...routePoints,
                clientLocation,
                ...routeDestinoPoints,
                destino,
              ], rotacionRad)
            : hasDriver
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
                    // puntos se salía del recuadro por el costado. Con
                    // destino, también entra el tramo cliente→destino.
                    ? ProyeccionMercator.boundsZoomRotado(
                        [
                          driver,
                          ...routePoints,
                          clientLocation,
                          ...routeDestinoPoints,
                          ?destino,
                        ],
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
                    : destino != null
                    // Sin conductor todavía (GPS sin fix) pero con destino
                    // conocido: encuadra cliente + destino en vez del zoom
                    // fijo, que dejaría el destino fuera del cuadro.
                    ? ProyeccionMercator.boundsZoomRotado(
                        [clientLocation, ...routeDestinoPoints, destino],
                        center: center,
                        rotacionRad: 0,
                        widthPx: width,
                        heightPx: height,
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

            // Mismo criterio para el tramo del viaje: la coordenada exacta
            // del cliente y del destino se anteponen/agregan para que la
            // traza salga/llegue justo desde/hacia ellos.
            final String? encodedPathDestino =
                destino != null && routeDestinoPoints.length >= 2
                ? _mapService.encodePolyline([
                    clientLocation,
                    ...routeDestinoPoints,
                    destino,
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
              isDark: Theme.of(context).brightness == Brightness.dark,
              encodedPath: encodedPath,
              encodedPathDestino: encodedPathDestino,
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
                  iconSize: _clienteIconSize,
                  child: Transform.rotate(
                    angle: -rotacionRad,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColores.primary,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
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
                if (destino != null)
                  _MapaPinOverlay(
                    offset: ProyeccionMercator.pixelOffset(
                      center: center,
                      point: destino,
                      zoom: zoom,
                    ),
                    boxWidth: lienzoAncho,
                    boxHeight: lienzoAlto,
                    iconSize: _destinoIconSize,
                    child: Transform.rotate(
                      angle: -rotacionRad,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColores.brand200,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.flag,
                          color: AppColores.primaryDark,
                          size: 16,
                        ),
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
    required bool isDark,
    String? encodedPath,
    String? encodedPathDestino,
  }) {
    // Static Maps admite varios `path=` en la misma URL (uno por tramo) —
    // `Uri.https` acepta una lista como valor de un query param y repite la
    // clave por cada elemento.
    final paths = [
      if (encodedPath != null)
        'color:0x${_routePathHex(AppColores.primary)}|weight:5|enc:$encodedPath',
      if (encodedPathDestino != null)
        'color:0x${_routePathHex(AppColores.brand200)}|weight:5|enc:$encodedPathDestino',
    ];
    final uri = Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom.floor().toString(),
      'size': '${width}x$height',
      'scale': '2',
      'maptype': 'roadmap',
      'key': apiKey,
      if (isDark) 'style': MapStyle.staticMapsQueryParams,
      if (paths.isNotEmpty) 'path': paths,
    });
    return uri.toString();
  }

  /// `RRGGBBAA` (Static Maps) desde un `Color` de Flutter con ~80% opacidad
  /// — se arma desde la constante de la app en vez de un hex suelto para no
  /// volver a desincronizarse si el color cambia.
  String _routePathHex(Color color) {
    final rgb = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '${rgb}CC';
  }
}

/// Posiciona un ícono exacto sobre un punto del mapa, dado su [offset] en
/// píxeles respecto al centro de la imagen — ancla el CENTRO del ícono
/// sobre el punto (los tres son badges circulares o vistas cenitales, no
/// pines/gota que necesiten anclar por la punta).
class _MapaPinOverlay extends StatelessWidget {
  const _MapaPinOverlay({
    required this.offset,
    required this.boxWidth,
    required this.boxHeight,
    required this.iconSize,
    required this.child,
  });

  final Offset offset;
  final double boxWidth;
  final double boxHeight;
  final double iconSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: boxWidth / 2 + offset.dx - iconSize / 2,
      top: boxHeight / 2 + offset.dy - iconSize / 2,
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
      color: context.palette.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(
        Icons.map_outlined,
        size: 40,
        color: context.palette.textSecondary.withValues(alpha: 0.6),
      ),
    );
  }
}

class _MapaPreviewCargando extends StatelessWidget {
  const _MapaPreviewCargando();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
