import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';

/// Tarjeta del mapa: marcador de origen (ícono de vehículo, según
/// `tipoVehiculo`) + marcador de destino (pin) + ruta trazada entre ambos.
/// Encuadra la cámara automáticamente para que los dos marcadores queden
/// visibles sin que el usuario tenga que mover el mapa con gestos.
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

  @override
  void initState() {
    super.initState();
    _cargarIconos();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
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
        final origen = data.origen.position;
        final destino = data.destino.position;
        final origenIcon =
            (data.tipoVehiculo == VehicleType.moto ? _motoIcon : _carIcon) ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColores.textPrimary, width: 1.5),
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
                Mapagoogle(
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
                if (data.isLoadingRoute)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.6),
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
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        backgroundColor: AppColores.surface,
                        foregroundColor: AppColores.textPrimary,
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
