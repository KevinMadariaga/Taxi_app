import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Componente reutilizable para renderizar Google Maps en la app.
///
/// Mantiene valores por defecto orientados a una experiencia interactiva,
/// pero expone opciones para que cada pantalla pueda personalizar el mapa.
class Mapagoogle extends StatelessWidget {
  final LatLng initialTarget;
  final double initialZoom;
  final Set<Marker> markers;
  final Set<Marker> customMarkers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final Set<Polygon> polygons;
  final ValueChanged<GoogleMapController>? onMapCreated;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ArgumentCallback<LatLng>? onTap;
  final ArgumentCallback<LatLng>? onLongPress;
  final EdgeInsets padding;
  final bool autoAdjustPaddingForSystemUI;
  final double topControlsOffset;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool zoomGesturesEnabled;
  final bool rotateGesturesEnabled;
  final bool tiltGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool compassEnabled;
  final bool mapToolbarEnabled;
  final bool trafficEnabled;
  final bool buildingsEnabled;
  final bool indoorViewEnabled;
  final MapType mapType;

  const Mapagoogle({
    super.key,
    required this.initialTarget,
    this.initialZoom = 15,
    this.markers = const {},
    this.customMarkers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.polygons = const {},
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.onLongPress,
    this.padding = EdgeInsets.zero,
    this.autoAdjustPaddingForSystemUI = true,
    this.topControlsOffset = 8,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = false,
    this.zoomControlsEnabled = false,
    this.zoomGesturesEnabled = true,
    this.rotateGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.compassEnabled = true,
    this.mapToolbarEnabled = true,
    this.trafficEnabled = false,
    this.buildingsEnabled = true,
    this.indoorViewEnabled = true,
    this.mapType = MapType.normal,
  }) : assert(initialZoom > 0);

  @override
  Widget build(BuildContext context) {
    final allMarkers = <Marker>{...markers, ...customMarkers};
    final showLocationButton = myLocationEnabled && myLocationButtonEnabled;
    final topInset = autoAdjustPaddingForSystemUI
        ? MediaQuery.of(context).padding.top + topControlsOffset
        : 0.0;
    final effectivePadding = EdgeInsets.fromLTRB(
      padding.left,
      padding.top + topInset,
      padding.right,
      padding.bottom,
    );

    // RepaintBoundary aísla la capa del mapa: evita que repintados de widgets
    // hermanos (overlays, animaciones de tarjetas) fuercen repintar el mapa,
    // reduciendo jank/caída de FPS.
    return RepaintBoundary(
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: initialTarget,
          zoom: initialZoom,
        ),
        markers: allMarkers,
        polylines: polylines,
        circles: circles,
        polygons: polygons,
        onMapCreated: onMapCreated,
        onCameraMove: onCameraMove,
        onCameraIdle: onCameraIdle,
        onTap: onTap,
        onLongPress: onLongPress,
        myLocationEnabled: myLocationEnabled,
        myLocationButtonEnabled: showLocationButton,
        zoomControlsEnabled: zoomControlsEnabled,
        zoomGesturesEnabled: zoomGesturesEnabled,
        rotateGesturesEnabled: rotateGesturesEnabled,
        tiltGesturesEnabled: tiltGesturesEnabled,
        scrollGesturesEnabled: scrollGesturesEnabled,
        compassEnabled: compassEnabled,
        mapToolbarEnabled: mapToolbarEnabled,
        trafficEnabled: trafficEnabled,
        buildingsEnabled: buildingsEnabled,
        indoorViewEnabled: indoorViewEnabled,
        mapType: mapType,
        padding: effectivePadding,
      ),
    );
  }
}
