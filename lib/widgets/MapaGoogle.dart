import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Mapagoogle extends StatefulWidget {
  final LatLng initialTarget;
  final double initialZoom;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final Function(GoogleMapController)? onMapCreated;
  final EdgeInsets padding;

  const Mapagoogle({
    super.key,
    required this.initialTarget,
    this.initialZoom = 15,
    this.markers = const {},
    this.polylines = const {},
    this.circles = const {},
    this.onMapCreated,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<Mapagoogle> createState() => _MapagoogleState();
}

class _MapagoogleState extends State<Mapagoogle> {

  final Completer<GoogleMapController> _controller =
    Completer<GoogleMapController>();

  void _onMapCreated(GoogleMapController c) {
    if (!_controller.isCompleted) {
      _controller.complete(c);
    }

    widget.onMapCreated?.call(c);
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialTarget,
        zoom: widget.initialZoom,
      ),
      markers: widget.markers,
      polylines: widget.polylines,
      circles: widget.circles,
      onMapCreated: _onMapCreated,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      zoomGesturesEnabled: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      compassEnabled: true,
      padding: widget.padding,
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}