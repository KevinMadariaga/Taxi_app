import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/map_style.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/core/utils/proyeccion_mercator.dart';

/// Mitad superior de la tarjeta de previsualización: `GoogleMap` real (no la
/// imagen estática de `MapaPrevisualizacionSolicitud`) — el conductor puede
/// mover/hacer zoom con gestos antes de decidir, con un botón para volver a
/// encuadrar todo (`_fitToPoints`).
///
/// Deliberadamente NO se reutiliza para `ViajeConductorScreen` (viaje ya en
/// curso): ese mapa estático se eligió a propósito para no mantener un
/// `GoogleMapController` en vivo corriendo de fondo del viaje — ver comentario
/// en `viaje_conductor_screen.dart`. Acá sí vale el costo porque, mientras la
/// preview está abierta, `InicioConductorView` YA desmonta el mapa en vivo del
/// home (`_HomeConductorIdleMap`) — no hay dos mapas en vivo compitiendo.
class MapaInteractivoPrevisualizacionSolicitud extends StatefulWidget {
  const MapaInteractivoPrevisualizacionSolicitud({
    super.key,
    required this.driverLocation,
    required this.clientLocation,
    this.isMoto = false,
    this.routePoints = const [],
    this.destinoLocation,
    this.routeDestinoPoints = const [],
  });

  final LatLng? driverLocation;
  final LatLng clientLocation;
  final bool isMoto;

  /// Ruta real (OSRM) conductor→cliente, si ya se resolvió.
  final List<LatLng> routePoints;

  /// Destino final del viaje — `null` si la solicitud no lo trae.
  final LatLng? destinoLocation;

  /// Ruta real (OSRM) cliente→destino, si ya se resolvió.
  final List<LatLng> routeDestinoPoints;

  @override
  State<MapaInteractivoPrevisualizacionSolicitud> createState() =>
      _MapaInteractivoPrevisualizacionSolicitudState();
}

class _MapaInteractivoPrevisualizacionSolicitudState
    extends State<MapaInteractivoPrevisualizacionSolicitud> {
  static const adapter.MapService _mapService = adapter.MapService();

  // Padding más chico que el default (80): esta tarjeta es más angosta que
  // un mapa a pantalla completa, mismo criterio que ya usaba el mapa
  // estático (`_margenHorizontal`/`_margenVertical` en
  // `MapaPrevisualizacionSolicitud`).
  static const double _paddingCamara = 72;
  static const double _zoomUnPunto = 16;

  GoogleMapController? _controller;
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _clienteIcon;
  BitmapDescriptor? _flagIcon;

  // El primer encuadre puede llegar sin `driverLocation` (GPS todavía sin
  // fix) — cuando el conductor aparece después se re-encuadra UNA vez para
  // incluirlo. Fuera de ese caso no se vuelve a mover la cámara sola: el
  // mapa es interactivo a propósito, un auto-refit periódico pisaría
  // cualquier gesto del conductor.
  bool _fitIncluyoConductor = false;

  @override
  void initState() {
    super.initState();
    _cargarIconos();
  }

  @override
  void didUpdateWidget(
    covariant MapaInteractivoPrevisualizacionSolicitud oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMoto != widget.isMoto) _cargarIconos();
    if (!_fitIncluyoConductor &&
        widget.driverLocation != null &&
        oldWidget.driverLocation == null) {
      _fitToPoints();
    }
  }

  Future<void> _cargarIconos() async {
    final resultados = await Future.wait([
      MarkerIconHelper.fromAsset(
        widget.isMoto
            ? 'assets/img/icono_moto.png'
            : 'assets/img/icono_carro.png',
        size: const Size(40, 40),
      ),
      // Badge de persona, no el pin/gota de marca: es un cliente esperando,
      // no un punto de interés genérico — mismo lenguaje visual que el
      // badge de bandera del destino, distinto color (naranja de marca
      // sólido, el mismo de la traza de recogida) para diferenciarlos.
      MarkerIconHelper.fromIcon(
        Icons.person,
        44,
        Colors.white,
        borderColor: Colors.white,
        backgroundColor: AppColores.primary,
      ),
      MarkerIconHelper.fromIcon(
        Icons.flag,
        44,
        AppColores.primaryDark,
        borderColor: Colors.white,
        backgroundColor: AppColores.brand200,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _carIcon = resultados[0];
      _clienteIcon = resultados[1];
      _flagIcon = resultados[2];
    });
  }

  List<LatLng> get _puntos => [
    if (widget.driverLocation != null) widget.driverLocation!,
    ...widget.routePoints,
    widget.clientLocation,
    ...widget.routeDestinoPoints,
    if (widget.destinoLocation != null) widget.destinoLocation!,
  ];

  Future<void> _fitToPoints() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final puntos = _puntos;
    if (puntos.isEmpty) return;

    final incluyeConductor = widget.driverLocation != null;
    final update = puntos.length < 2
        ? _mapService.cameraToPosition(puntos.first, zoom: _zoomUnPunto)
        : _mapService.cameraToBoundsFromPoints(puntos, padding: _paddingCamara);
    if (update == null) return;

    // `newLatLngBounds` puede fallar si el mapa todavía no tiene su tamaño
    // final layouteado justo tras `onMapCreated` — un reintento tras un
    // frame alcanza. Mismo patrón que `mapa_ruta_card.dart` y
    // `viaje_cliente_screen.dart`, que ya tropezaron con esto.
    if (await _intentarAnimar(controller, update)) {
      _fitIncluyoConductor = incluyeConductor;
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));
    // El controller pudo quedar obsoleto durante el delay (mapa remontado):
    // usarlo igual lanza "GoogleMapController ... was used after the
    // associated GoogleMap widget had already been disposed".
    if (!mounted || !identical(_controller, controller)) return;
    if (await _intentarAnimar(controller, update)) {
      _fitIncluyoConductor = incluyeConductor;
    }
    // Si vuelve a fallar NO se marca `_fitIncluyoConductor`: así el
    // re-encuadre automático de `didUpdateWidget` (cuando llegue el GPS)
    // sigue disponible en vez de quedar deshabilitado por un intento fallido.
  }

  Future<bool> _intentarAnimar(
    GoogleMapController controller,
    CameraUpdate update,
  ) async {
    try {
      await controller.animateCamera(update);
      return true;
    } catch (_) {
      // Best-effort: si falla del todo, el conductor encuadra a mano con
      // gestos o con el botón de centrar.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driverLocation;
    final destino = widget.destinoLocation;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('cliente'),
        position: widget.clientLocation,
        anchor: const Offset(0.5, 0.5),
        icon:
            _clienteIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('conductor'),
          position: driver,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: ProyeccionMercator.bearingDegrees(
            driver,
            widget.clientLocation,
          ),
          icon:
              _carIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                widget.isMoto
                    ? BitmapDescriptor.hueGreen
                    : BitmapDescriptor.hueAzure,
              ),
        ),
      if (destino != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destino,
          anchor: const Offset(0.5, 0.5),
          icon:
              _flagIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              ),
        ),
    };

    final polylines = <Polyline>{
      if (widget.routePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('recogida'),
          points: widget.routePoints,
          color: AppColores.primary,
          width: 5,
        ),
      // Mismo naranja de marca que la recogida, más claro — se lee como "un
      // solo viaje" en vez de un color ajeno, diferenciable por intensidad.
      if (widget.routeDestinoPoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('viaje'),
          points: widget.routeDestinoPoints,
          color: AppColores.brand200,
          width: 5,
        ),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: driver ?? widget.clientLocation,
            zoom: 15,
          ),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          style: Theme.of(context).brightness == Brightness.dark
              ? MapStyle.googleMapJson
              : null,
          markers: markers,
          polylines: polylines,
          onMapCreated: (controller) {
            _controller = controller;
            // Post-frame: `onMapCreated` dispara antes de que el mapa tenga
            // su tamaño final, y `newLatLngBounds` falla sin layout.
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _fitToPoints(),
            );
          },
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: FloatingActionButton(
            heroTag: 'centrarPreviewSolicitud',
            mini: true,
            backgroundColor: context.palette.surface,
            foregroundColor: context.palette.textPrimary,
            onPressed: _fitToPoints,
            child: const Icon(Icons.center_focus_strong),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}
