import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

/// Mapa de la pantalla "buscando taxi": traza la ruta real (por calle) entre
/// la ubicación de recogida del cliente y el destino de la solicitud, y
/// muestra los conductores disponibles/conectados cerca.
///
/// Reemplaza al antiguo `SonarMapWidget` (anillos de radar centrados en el
/// cliente): con un destino real que mostrar, el mapa ahora encuadra ambos
/// puntos (origen + destino) en vez de quedar fijo sobre el cliente, así que
/// un radar centrado en pantalla ya no tenía un punto de referencia estable
/// donde dibujarse.
class SearchRouteMapWidget extends StatefulWidget {
  const SearchRouteMapWidget({
    super.key,
    required this.clientLocation,
    required this.destinoLocation,
    required this.routePoints,
    required this.conductoresPositions,
    required this.conectadosPositions,
    required this.isMoto,
    required this.onMapCreated,
  });

  final LatLng? clientLocation;
  final LatLng? destinoLocation;
  final List<LatLng> routePoints;
  final Map<String, LatLng> conductoresPositions;
  final Map<String, LatLng> conectadosPositions;
  final bool isMoto;
  final void Function(GoogleMapController) onMapCreated;

  @override
  State<SearchRouteMapWidget> createState() => _SearchRouteMapWidgetState();
}

class _SearchRouteMapWidgetState extends State<SearchRouteMapWidget> {
  static const _defaultCenter = LatLng(8.2595534, -73.353469);

  GoogleMapController? _controller;

  BitmapDescriptor? _origenIcon;
  BitmapDescriptor? _destinoIcon;
  BitmapDescriptor? _taxiIcon;
  BitmapDescriptor? _motoIcon;
  Set<Marker> _driverMarkers = {};

  // Encuadre de cámara a [origen, destino]: se hace una sola vez, apenas
  // ambos puntos y el controller están disponibles (mismo criterio de
  // "una sola vez" que el cálculo de ruta en el ViewModel).
  bool _boundsFitted = false;

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _updateDriverMarkers();
  }

  Future<void> _loadIcons() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;

      final origenIcon = await MarkerIconHelper.fromIcon(
        Icons.trip_origin,
        40,
        Colors.white,
        backgroundColor: AppColores.primary,
        backgroundScale: 0.7,
        borderColor: Colors.white,
      );
      // Mismo pin rojo que el resto de la app usa para el destino
      // (ConfirmarSolicitudView, RutaClienteDestinoView, RutaDestinoView,
      // driver_trip_screen) — antes esta pantalla era la única que dibujaba
      // un ícono de bandera genérico en vez de reusar el asset de marca.
      final destinoIcon = await MarkerIconHelper.fromAsset(
        'assets/img/map_pin_red.png',
        size: const Size(48, 48),
        devicePixelRatio: dpr,
      );
      // Íconos reales de vehículo (mismos assets que trip_tracking_screen
      // usa para el conductor en curso) en vez del badge circular genérico
      // dibujado con un ícono de Material.
      final taxiIcon = await MarkerIconHelper.fromAsset(
        'assets/img/icono_carro.png',
        size: const Size(40, 40),
      );
      final motoIcon = await MarkerIconHelper.fromAsset(
        'assets/img/icono_moto.png',
        size: const Size(40, 40),
      );
      if (!mounted) return;
      _origenIcon = origenIcon;
      _destinoIcon = destinoIcon;
      _taxiIcon = taxiIcon;
      _motoIcon = motoIcon;
      _updateDriverMarkers();
      setState(() {});
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'search_route_map_widget');
    }
  }

  @override
  void didUpdateWidget(covariant SearchRouteMapWidget old) {
    super.didUpdateWidget(old);
    if (old.conductoresPositions != widget.conductoresPositions ||
        old.conectadosPositions != widget.conectadosPositions ||
        old.isMoto != widget.isMoto) {
      _updateDriverMarkers();
    }
    if (old.clientLocation != widget.clientLocation ||
        old.destinoLocation != widget.destinoLocation) {
      _maybeFitBounds();
    }
  }

  void _updateDriverMarkers() {
    final isMoto = widget.isMoto;
    final icon = isMoto
        ? (_motoIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange))
        : (_taxiIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ));

    // `conductoresPositions` (usuarios/disponible) y `conectadosPositions`
    // (conductores_conectados) suelen traer al mismo conductor por ser
    // colecciones distintas para el mismo estado — se excluye de la primera
    // el que ya está en la segunda para no duplicar el ícono en el mapa.
    final markers = <Marker>{
      for (final e in widget.conductoresPositions.entries)
        if (!widget.conectadosPositions.containsKey(e.key))
          Marker(
            markerId: MarkerId('taxi_${e.key}'),
            position: e.value,
            icon: icon,
            infoWindow: InfoWindow(
              title: isMoto ? 'Moto cercana' : 'Taxi cercano',
            ),
          ),
      for (final e in widget.conectadosPositions.entries)
        Marker(
          markerId: MarkerId('conectado_${e.key}'),
          position: e.value,
          icon: icon,
          infoWindow: InfoWindow(
            title: isMoto ? 'Moto conectada' : 'Conductor conectado',
          ),
        ),
    };
    if (!mounted) return;
    setState(() => _driverMarkers = markers);
  }

  void _maybeFitBounds() {
    if (_boundsFitted) return;
    final controller = _controller;
    final origen = widget.clientLocation;
    final destino = widget.destinoLocation;
    if (controller == null || origen == null || destino == null) return;

    _boundsFitted = true;
    final sw = LatLng(
      origen.latitude < destino.latitude ? origen.latitude : destino.latitude,
      origen.longitude < destino.longitude
          ? origen.longitude
          : destino.longitude,
    );
    final ne = LatLng(
      origen.latitude > destino.latitude ? origen.latitude : destino.latitude,
      origen.longitude > destino.longitude
          ? origen.longitude
          : destino.longitude,
    );
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        72,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final origen = widget.clientLocation ?? _defaultCenter;

    final markers = <Marker>{
      ..._driverMarkers,
      if (widget.clientLocation != null)
        Marker(
          markerId: const MarkerId('origen_busqueda'),
          position: widget.clientLocation!,
          icon:
              _origenIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Tu ubicación'),
          zIndexInt: 2,
        ),
      if (widget.destinoLocation != null)
        Marker(
          markerId: const MarkerId('destino_busqueda'),
          position: widget.destinoLocation!,
          icon:
              _destinoIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destino'),
          zIndexInt: 2,
        ),
    };

    // Ruta con "casing": una línea ancha oscura debajo + una angosta del
    // color de marca encima — la misma técnica que usa Google Maps para que
    // la ruta se lea nítida sin importar el color del mapa debajo (calles
    // claras, parques verdes, agua azul, etc.), en vez de un trazo plano de
    // un solo color que a veces se pierde contra el fondo.
    final polylines = <Polyline>{
      if (widget.routePoints.length >= 2) ...[
        Polyline(
          polylineId: const PolylineId('ruta_busqueda_casing'),
          points: widget.routePoints,
          color: const Color(0xFF1A1A2E),
          width: 9,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ),
        Polyline(
          polylineId: const PolylineId('ruta_busqueda'),
          points: widget.routePoints,
          color: AppColores.primary,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 2,
        ),
      ],
    };

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Mapagoogle(
        initialTarget: origen,
        initialZoom: 15,
        markers: markers,
        polylines: polylines,
        onMapCreated: (controller) {
          _controller = controller;
          widget.onMapCreated(controller);
          _maybeFitBounds();
        },
        // A diferencia del radar (puramente decorativo), este mapa muestra
        // una ruta real: tiene sentido dejar que el usuario la explore.
        zoomGesturesEnabled: true,
        scrollGesturesEnabled: true,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        compassEnabled: false,
        mapToolbarEnabled: false,
        myLocationButtonEnabled: false,
      ),
    );
  }
}
