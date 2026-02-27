import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Modelo para representar una ubicación con título y subtítulo opcionales.
class LocationModel {
  final LatLng position;
  final String? title;
  final String? subtitle;

  const LocationModel({
    required this.position,
    this.title,
    this.subtitle,
  });
}
