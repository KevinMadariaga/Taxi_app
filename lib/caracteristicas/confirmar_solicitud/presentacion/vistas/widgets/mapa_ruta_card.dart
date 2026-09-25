import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';
import 'package:taxi_app/core/modelos/location_model.dart';
import 'package:taxi_app/core/modelos/vehicle_type.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

/// Tarjeta del mapa: marcador de origen (ícono de vehículo, según
/// `tipoVehiculo`) + marcador de destino (pin) + ruta trazada entre ambos.
/// Encuadra la cámara automáticamente para que los dos marcadores queden
/// visibles sin que el usuario tenga que mover el mapa con gestos.
///
/// Después del encuadre, el mapa se orienta con la brújula del teléfono y
/// con perspectiva (inclinado): lo que el cliente tiene enfrente queda
/// arriba en pantalla, así no tiene que girar el teléfono ni deducir hacia
/// dónde va su calle. Sin sensor de brújula se orienta en la dirección
/// origen → destino. Tocar y arrastrar el mapa suelta el seguimiento; el
/// botón "Orientar" lo retoma y el de brújula vuelve a norte arriba.
class MapaRutaCard extends StatefulWidget {
  const MapaRutaCard({super.key});

  @override
  State<MapaRutaCard> createState() => _MapaRutaCardState();
}

class _MapaRutaCardState extends State<MapaRutaCard> {
  static const double _boundsPadding = 72;

  GoogleMapController? _controller;
  BitmapDescriptor? _destIcon;
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _motoIcon;

  /// Rumbo actual del mapa — alimenta el botón de brújula (visible mientras
  /// el usuario rotó el mapa con gestos) y la rotación del ícono de la
  /// brújula, igual que en `viaje_cliente_screen.dart`.
  final ValueNotifier<double> _bearingNotifier = ValueNotifier<double>(0);

  // ── Brújula + perspectiva ─────────────────────────────────────────────
  static const double _inclinacion = 45;

  /// Cambios menores a esto no mueven la cámara (el sensor tiembla).
  static const double _umbralGrados = 4;

  /// Como mucho una animación de cámara cada este tiempo: el sensor emite
  /// decenas de eventos por segundo.
  static const Duration _intervaloMinimo = Duration(milliseconds: 350);

  final ValueNotifier<bool> _siguiendo = ValueNotifier<bool>(true);
  StreamSubscription<CompassEvent>? _brujulaSub;
  double? _rumboSensor;
  double? _ultimoRumboAplicado;
  DateTime _ultimaAnimacion = DateTime.fromMillisecondsSinceEpoch(0);
  bool _vistaLista = false;
  Set<Polyline>? _polylinesVistas;
  Offset? _inicioToque;

  @override
  void initState() {
    super.initState();
    _cargarIconos();
    _brujulaSub = FlutterCompass.events?.listen(
      _onBrujula,
      // Equipo sin magnetómetro o canal no disponible: se queda la
      // orientación por la ruta (ver `_rumboObjetivo`).
      onError: (Object _) {},
    );
  }

  void _onBrujula(CompassEvent e) {
    final h = e.heading;
    if (h == null) return;
    _rumboSensor = (h + 360) % 360;
    // Con otra pantalla encima (buscando conductor) no hay nada que mover.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _aplicarRumbo();
  }

  /// Rumbo a mostrar arriba: el de la brújula; sin sensor, la dirección
  /// de la ruta (origen → destino).
  double _rumboObjetivo() {
    if (_rumboSensor != null) return _rumboSensor!;
    final vm = context.read<ConfirmarSolicitudViewModel>();
    return ProyeccionMercator.bearingDegrees(
      vm.origen.position,
      vm.destino.position,
    );
  }

  /// Origen, destino y todos los puntos del trazado: el encuadre tiene que
  /// contener la ruta completa, no solo sus extremos (una ruta que rodea
  /// una manzana se sale del recuadro de inicio-fin).
  List<LatLng> _puntosRuta() {
    final vm = context.read<ConfirmarSolicitudViewModel>();
    return [
      vm.origen.position,
      vm.destino.position,
      for (final p in vm.polylines) ...p.points,
    ];
  }

  /// Centro del recuadro de la ruta completa.
  LatLng _centro(List<LatLng> puntos) {
    var minLat = puntos.first.latitude, maxLat = minLat;
    var minLng = puntos.first.longitude, maxLng = minLng;
    for (final p in puntos) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
  }

  /// Zoom más cercano en el que la ruta completa entra en el mapa **con el
  /// rumbo dado** (al rotar, lo que cabe cambia). Margen vertical mayor que
  /// el horizontal: con la inclinación, la parte de abajo se ve más grande.
  double? _zoomPara(double rumbo, List<LatLng> puntos, LatLng centro) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return ProyeccionMercator.boundsZoomRotado(
      puntos,
      center: centro,
      rotacionRad: ProyeccionMercator.rotacionParaRumboArriba(rumbo),
      widthPx: box.size.width,
      heightPx: box.size.height,
      margenHorizontal: 70,
      margenVertical: 130,
      zoomMax: 17.5,
    );
  }

  Future<void> _aplicarRumbo({bool forzar = false}) async {
    final controller = _controller;
    if (!mounted || !_vistaLista || !_siguiendo.value || controller == null) {
      return;
    }
    final rumbo = _rumboObjetivo();
    final ahora = DateTime.now();
    if (!forzar) {
      final previo = _ultimoRumboAplicado;
      if (previo != null &&
          ProyeccionMercator.diferenciaAngular(rumbo, previo) < _umbralGrados) {
        return;
      }
      if (ahora.difference(_ultimaAnimacion) < _intervaloMinimo) return;
    }
    final puntos = _puntosRuta();
    final centro = _centro(puntos);
    final zoom = _zoomPara(rumbo, puntos, centro);
    if (zoom == null) return;
    _ultimoRumboAplicado = rumbo;
    _ultimaAnimacion = ahora;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: centro,
            zoom: zoom,
            bearing: rumbo,
            tilt: _inclinacion,
          ),
        ),
      );
    } catch (e, st) {
      // Mapa remontado (cambió origen/destino) mientras animaba: el
      // controller viejo ya no sirve y el nuevo rehace la vista.
      if (identical(_controller, controller)) {
        ErrorReporter.report(e, st, reason: 'mapa_ruta_card: brujula');
      }
    }
  }

  /// Centro del recorrido y primera vista con perspectiva. Sin brújula ni
  /// seguimiento, queda el encuadre norte-arriba de siempre.
  Future<void> _iniciarVista() async {
    if (!mounted) return;
    _vistaLista = true;
    _ultimoRumboAplicado = null;
    if (_siguiendo.value) {
      await _aplicarRumbo(forzar: true);
    } else {
      await _fitBounds();
    }
  }

  void _pausarSeguimiento() {
    if (!_siguiendo.value) return;
    _siguiendo.value = false;
    _brujulaSub?.pause();
  }

  void _reanudarSeguimiento() {
    _siguiendo.value = true;
    if (_brujulaSub?.isPaused ?? false) _brujulaSub!.resume();
    _ultimoRumboAplicado = null;
    unawaited(_aplicarRumbo(forzar: true));
  }

  // `MarkerIconHelper.fromAsset` (a diferencia de `BitmapDescriptor.asset`)
  // ajusta el asset con `BoxFit.contain` dentro del tamaño pedido en vez de
  // estirarlo — `icono_carro.png`/`icono_moto.png` son angostos (65x126, no
  // cuadrados), así que pedirlos en una caja cuadrada con `BitmapDescriptor
  // .asset` los deformaba (se veían anchos/aplastados en el mapa).
  Future<void> _cargarIconos() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      final results = await Future.wait([
        MarkerIconHelper.fromAsset(
          'assets/img/map_pin_red.png',
          size: const Size(48, 48),
          devicePixelRatio: dpr,
        ),
        MarkerIconHelper.fromAsset(
          'assets/img/icono_carro.png',
          size: const Size(40, 40),
          devicePixelRatio: dpr,
        ),
        MarkerIconHelper.fromAsset(
          'assets/img/icono_moto.png',
          size: const Size(40, 40),
          devicePixelRatio: dpr,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _destIcon = results[0];
        _carIcon = results[1];
        _motoIcon = results[2];
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'mapa_ruta_card');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _vistaLista = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _iniciarVista());
  }

  /// Encuadra la cámara al bounding box de origen+destino. `newLatLngBounds`
  /// (a diferencia de `newCameraPosition`) puede fallar si el mapa todavía
  /// no tiene su tamaño final layouteado justo tras `onMapCreated` — un
  /// reintento tras el siguiente frame alcanza.
  Future<void> _fitBounds() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final bounds = context
        .read<ConfirmarSolicitudViewModel>()
        .boundsOrigenDestino;
    final update = CameraUpdate.newLatLngBounds(bounds, _boundsPadding);
    try {
      await controller.animateCamera(update);
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 300));
      // Durante el delay el mapa pudo remontarse: la `ValueKey` de más abajo
      // depende de origen+destino, así que mover un pin destruye el `GoogleMap`
      // y crea otro. Este `State` NO se desmonta en ese caso —solo su hijo—,
      // por eso `mounted` sigue siendo true y no alcanza como guarda: hay que
      // comprobar que el controller capturado siga siendo el vigente. Usarlo
      // igual lanzaba "GoogleMapController ... was used after the associated
      // GoogleMap widget had already been disposed" (visto en dispositivo real,
      // un error reportado a Crashlytics por cada ajuste de pin).
      if (!mounted || !identical(_controller, controller)) return;
      try {
        await controller.animateCamera(update);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'mapa_ruta_card');
      }
    }
  }

  // No hay reencuadre manual al cambiar origen/destino: la `ValueKey` del
  // mapa depende de esas mismas coordenadas, así que mover un pin remonta el
  // `GoogleMap` y el `onMapCreated` del mapa nuevo ya hace el `_fitBounds`.
  // Antes había un `_reencuadrarSiCambio()` llamado desde `build` que
  // duplicaba ese trabajo y, peor, programaba un `_fitBounds` que corría con
  // el controller del mapa ANTERIOR (ya destruido por el remonte) — la fuente
  // del "GoogleMapController ... used after ... disposed" de cada ajuste.

  /// Botón de brújula: restablece norte arriba (`_fitBounds` deja bearing y
  /// tilt en 0) y reencuadra origen+destino — mismo criterio que
  /// `viaje_cliente_screen.dart._restablecerOrientacionMapa`.
  void _restablecerOrientacion() {
    _pausarSeguimiento();
    _bearingNotifier.value = 0;
    unawaited(_fitBounds());
  }

  @override
  void dispose() {
    // El controller NO se dispone a mano: `GoogleMapState.dispose()` del
    // plugin ya lo hace cuando el `GoogleMap` se desmonta. Hacerlo aquí era un
    // doble dispose y, tras un remonte por la `ValueKey`, se ejecutaba además
    // sobre un controller que ya no era el vigente.
    _controller = null;
    _brujulaSub?.cancel();
    _siguiendo.dispose();
    _bearingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<
      ConfirmarSolicitudViewModel,
      ({
        LocationModel origen,
        LocationModel destino,
        Set<Polyline> polylines,
        bool isLoadingRoute,
        VehicleType tipoVehiculo,
      })
    >(
      selector: (context, vm) => (
        origen: vm.origen,
        destino: vm.destino,
        polylines: vm.polylines,
        isLoadingRoute: vm.isLoadingRoute,
        tipoVehiculo: vm.tipoVehiculo,
      ),
      builder: (context, data, _) {
        // El trazado llega después de crear el mapa (se calcula aparte):
        // al llegar, reencuadrar para que la vista lo contenga completo.
        if (!identical(data.polylines, _polylinesVistas)) {
          _polylinesVistas = data.polylines;
          if (_vistaLista && _siguiendo.value) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _aplicarRumbo(forzar: true),
            );
          }
        }
        final origen = data.origen.position;
        final destino = data.destino.position;
        final origenIcon =
            (data.tipoVehiculo == VehicleType.moto ? _motoIcon : _carIcon) ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.palette.textPrimary, width: 1.5),
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Stack(
              children: [
                // Arrastrar/rotar con el dedo suelta el seguimiento de la
                // brújula (si no, la cámara le "pelearía" el gesto). Un
                // toque corto (abrir info del marcador) no cuenta.
                Listener(
                  onPointerDown: (e) => _inicioToque = e.position,
                  onPointerMove: (e) {
                    final inicio = _inicioToque;
                    if (inicio != null && (e.position - inicio).distance > 12) {
                      _pausarSeguimiento();
                    }
                  },
                  onPointerUp: (_) => _inicioToque = null,
                  child: Mapagoogle(
                    // La key depende de origen, destino Y tipo de vehículo (no
                    // solo destino): en iOS, actualizar solo la `position` o
                    // el `icon` de un `Marker` con el mismo `markerId` a veces
                    // no se refleja en el mapa nativo (el plugin no siempre
                    // repinta el marcador con el diffing por posición/ícono).
                    // Incluir el tipo de vehículo fuerza a remontar el
                    // `GoogleMap` cuando el usuario cambia carro↔moto, en vez
                    // de depender de esa actualización in-place.
                    key: ValueKey(
                      '${origen.latitude},${origen.longitude}_'
                      '${destino.latitude},${destino.longitude}_'
                      '${data.tipoVehiculo.firestoreKey}',
                    ),
                    initialTarget: LatLng(
                      (origen.latitude + destino.latitude) / 2,
                      (origen.longitude + destino.longitude) / 2,
                    ),
                    initialZoom: 13,
                    // Marcador propio de vehículo en vez del punto azul nativo
                    // de "Mi ubicación": `origen` puede diferir del GPS real
                    // (el cliente lo ajusta manualmente), así que el punto
                    // nativo podía mostrar una posición distinta a la que
                    // realmente se usa en la solicitud.
                    myLocationEnabled: false,
                    onMapCreated: _onMapCreated,
                    onCameraMove: (position) {
                      _bearingNotifier.value = position.bearing;
                    },
                    markers: {
                      Marker(
                        markerId: const MarkerId('origen'),
                        position: origen,
                        anchor: const Offset(0.5, 0.5),
                        infoWindow: InfoWindow(
                          title: data.origen.title ?? 'Tu ubicación',
                          snippet: data.origen.subtitle,
                        ),
                        icon: origenIcon,
                      ),
                      Marker(
                        markerId: const MarkerId('destino'),
                        position: destino,
                        infoWindow: InfoWindow(
                          title: data.destino.title ?? 'Destino',
                          snippet: data.destino.subtitle,
                        ),
                        icon:
                            _destIcon ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed,
                            ),
                      ),
                    },
                    polylines: data.polylines,
                  ),
                ),
                if (data.isLoadingRoute)
                  Positioned.fill(
                    child: Container(
                      color: context.palette.background.withValues(alpha: 0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: AppColores.primary,
                            ),
                            SizedBox(height: 12.h),
                            Text(
                              'Cargando ruta...',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16.sp,
                                color: context.palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 10.w,
                  top: 10.h,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _siguiendo,
                    builder: (context, siguiendo, _) => AnimatedOpacity(
                      opacity: siguiendo ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _ChipOrientacion(
                        texto: _rumboSensor != null
                            ? 'Orientado a tu vista'
                            : 'Orientado hacia tu destino',
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10.w,
                  bottom: 62.h,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _siguiendo,
                    builder: (context, siguiendo, _) {
                      if (siguiendo) return const SizedBox.shrink();
                      return FloatingActionButton(
                        heroTag: 'orientarMapaRuta',
                        mini: true,
                        tooltip: 'Orientar a mi vista',
                        backgroundColor: AppColores.buttonPrimary,
                        foregroundColor: Colors.black,
                        onPressed: _reanudarSeguimiento,
                        child: const Icon(Icons.navigation_rounded),
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 10.w,
                  bottom: 10.h,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _bearingNotifier,
                    builder: (context, bearing, _) {
                      if (bearing.abs() < 0.5) return const SizedBox.shrink();
                      return FloatingActionButton(
                        heroTag: 'brujulaMapaRuta',
                        mini: true,
                        tooltip: 'Norte arriba',
                        backgroundColor: context.palette.surface,
                        foregroundColor: context.palette.textPrimary,
                        onPressed: _restablecerOrientacion,
                        child: Transform.rotate(
                          // Igual que en `viaje_cliente_screen.dart`: la
                          // aguja gira al revés de la rotación del mapa para
                          // seguir señalando el norte real.
                          angle: -bearing * math.pi / 180,
                          child: const Icon(Icons.explore),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChipOrientacion extends StatelessWidget {
  const _ChipOrientacion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_rounded, size: 15, color: palette.textPrimary),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
