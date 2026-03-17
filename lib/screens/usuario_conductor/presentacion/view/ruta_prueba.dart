import 'package:flutter/material.dart';
import 'package:taxi_app/features/driver_trip/screens/driver_trip_screen.dart';

class RutaConductor extends StatelessWidget {
  const RutaConductor({super.key, required this.idSolicitud});

  final String idSolicitud;

  @override
  Widget build(BuildContext context) {
    return DriverTripScreen(tripId: idSolicitud);
  }
}
