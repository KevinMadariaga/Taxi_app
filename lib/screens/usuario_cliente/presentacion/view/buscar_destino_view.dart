import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/SeleccionDestino.dart';

/// Vista de busqueda de destino del cliente.
/// Encapsula la implementacion actual de seleccion de destino.
class BuscarDestinoView extends StatelessWidget {
  const BuscarDestinoView({
    super.key,
    this.currentLocation,
    this.origenDireccionInicial,
  });

  final LatLng? currentLocation;
  final String? origenDireccionInicial;

  @override
  Widget build(BuildContext context) {
    return DestinoSeleccionView(
      currentLocation: currentLocation,
      origenDireccionInicial: origenDireccionInicial,
    );
  }
}
