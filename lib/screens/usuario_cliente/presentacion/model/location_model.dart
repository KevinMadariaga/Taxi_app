import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationModel {
  final LatLng position;
  final String? title;
  final String? subtitle;

  LocationModel({required this.position, this.title, this.subtitle});
}
