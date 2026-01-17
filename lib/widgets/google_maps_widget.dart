import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AppGoogleMap extends StatefulWidget {
	final LatLng initialTarget;
	final double initialZoom;
	final Set<Marker> markers;
	final Set<Polyline> polylines;
	final ValueChanged<GoogleMapController>? onMapCreated;
	final ValueChanged<CameraPosition>? onCameraMove;
	final VoidCallback? onCameraIdle;
	final VoidCallback? onMapLoaded;
	final MapType mapType;
	final bool myLocationEnabled;
	final bool myLocationButtonEnabled;
	final bool compassEnabled;
	final EdgeInsets padding;

	const AppGoogleMap({
		super.key,
		required this.initialTarget,
		this.initialZoom = 15.0,
		this.markers = const <Marker>{},
		this.polylines = const <Polyline>{},
		this.onMapCreated,
		this.onCameraMove,
		this.onCameraIdle,
		this.onMapLoaded,
		this.mapType = MapType.normal,
		this.myLocationEnabled = false,
		this.myLocationButtonEnabled = false,
		this.compassEnabled = true,
		this.padding = EdgeInsets.zero,
	});

	@override
	State<AppGoogleMap> createState() => _AppGoogleMapState();
}

class _AppGoogleMapState extends State<AppGoogleMap> {
	GoogleMapController? _controller;

	Future<void> _handleMapCreated(GoogleMapController controller) async {
		_controller = controller;
		debugPrint('AppGoogleMap: onMapCreated callback');
		widget.onMapCreated?.call(controller);
		// Intentar obtener la región visible para asegurarnos de que el mapa
		// responde y ha cargado recursos básicos; cuando esto complete, llamar
		// al callback de "map loaded".
		try {
			await controller.getVisibleRegion();
			debugPrint('AppGoogleMap: getVisibleRegion OK');
			widget.onMapLoaded?.call();
		} catch (e) {
			debugPrint('AppGoogleMap: getVisibleRegion failed: $e');
			// Si falla, llamar al callback igualmente para no bloquear la UI.
			widget.onMapLoaded?.call();
		}
	}

	@override
	Widget build(BuildContext context) {
		return GoogleMap(
			initialCameraPosition: CameraPosition(
				target: widget.initialTarget,
				zoom: widget.initialZoom,
			),
			mapType: widget.mapType,
			markers: widget.markers,
			polylines: widget.polylines,
			myLocationEnabled: widget.myLocationEnabled,
			myLocationButtonEnabled: widget.myLocationButtonEnabled,
			compassEnabled: widget.compassEnabled,
			onMapCreated: _handleMapCreated,
			onCameraMove: widget.onCameraMove,
			onCameraIdle: widget.onCameraIdle,
			padding: widget.padding,
			zoomControlsEnabled: false,
			zoomGesturesEnabled: true,
			scrollGesturesEnabled: true,
			rotateGesturesEnabled: true,
			tiltGesturesEnabled: true,
		);
	}
}


