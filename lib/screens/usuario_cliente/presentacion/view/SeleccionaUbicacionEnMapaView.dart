import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Vista para seleccionar una ubicación en el mapa.
class SeleccionaUbicacionEnMapaView extends StatefulWidget {
  final LatLng ubicacionInicial;
  final String? titulo;

  const SeleccionaUbicacionEnMapaView({
    super.key,
    required this.ubicacionInicial,
    this.titulo,
  });

  @override
  State<SeleccionaUbicacionEnMapaView> createState() => _SeleccionaUbicacionEnMapaViewState();
}

class _SeleccionaUbicacionEnMapaViewState extends State<SeleccionaUbicacionEnMapaView> {
  late LatLng _center;
  GoogleMapController? _mapController;
  String _direccion = '';

  @override
  void initState() {
    super.initState();
    _center = widget.ubicacionInicial;
    _actualizarDireccion(_center);
  }

  Future<void> _actualizarDireccion(LatLng coord) async {
    try {
      final placemarks = await placemarkFromCoordinates(coord.latitude, coord.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = [p.street, p.subLocality, p.locality, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        setState(() {
          _direccion = direccion.isNotEmpty
              ? direccion
              : '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      setState(() {
        _direccion = '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    setState(() {
      _center = position.target;
    });
    _actualizarDireccion(position.target);
  }

  void _onConfirmarUbicacion() {
    Navigator.of(context).pop(_center);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double mapHeight = size.height * 0.55;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo ?? 'Selecciona ubicación'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 12),
            Center(
              child: SizedBox(
                height: mapHeight,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _center,
                            zoom: 16,
                          ),
                          onMapCreated: _onMapCreated,
                          onCameraMove: _onCameraMove,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Transform.translate(
                        offset: const Offset(0, -18),
                        child: const Icon(
                          Icons.place,
                          size: 48,
                          color: Color(0xFFFFCA44),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'Mueve el mapa para seleccionar la ubicación',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.amber, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _direccion.isNotEmpty
                              ? _direccion
                              : 'Buscando dirección...',
                          style: const TextStyle(fontSize: 15, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colores.amarillo,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onPressed: _onConfirmarUbicacion,
                  child: const Text(
                    'Confirmar ubicación',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
