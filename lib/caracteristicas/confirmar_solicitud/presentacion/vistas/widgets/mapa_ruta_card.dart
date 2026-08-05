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
  LatLngBounds? _ultimoBoundsAjustado;

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
    _ultimoBoundsAjustado = bounds;
    final update = CameraUpdate.newLatLngBounds(bounds, _boundsPadding);
    try {
      await controller.animateCamera(update);
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await controller.animateCamera(update);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'mapa_ruta_card');
      }
    }
  }

  /// Reencuadra cuando origen/destino cambian (el cliente ajustó un pin) —
  /// se llama desde `build`, así que se compara contra el último bounds ya
  /// aplicado para no relanzar `animateCamera` en cada notify sin cambios
  /// reales de posición.
  void _reencuadrarSiCambio() {
    if (_controller == null) return;
    final bounds = context
        .read<ConfirmarSolicitudViewModel>()
        .boundsOrigenDestino;
    if (_ultimoBoundsAjustado == bounds) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
  }

  @override
  void dispose() {
    _controller?.dispose();
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
        _reencuadrarSiCambio();
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
                  // La key depende de origen Y destino (no solo destino):
                  // en iOS, actualizar solo la `position` de un `Marker` con
                  // el mismo `markerId` a veces no se refleja en el mapa
                  // nativo (el plugin no siempre repinta el marcador con el
                  // diffing por posición). Incluir el origen fuerza a
                  // remontar el `GoogleMap` con los marcadores ya en su
                  // posición final en vez de depender de esa actualización.
                  key: ValueKey(
                    '${origen.latitude},${origen.longitude}_'
                    '${destino.latitude},${destino.longitude}',
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
              ],
            ),
          ),
        );
      },
    );
  }
}
