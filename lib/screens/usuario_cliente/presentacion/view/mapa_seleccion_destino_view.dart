import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';

import 'package:taxi_app/screens/usuario_cliente/presentacion/view/solicitud_preview_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/mapapreview_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';

class MapaPreviewView extends StatefulWidget {
  final LatLng location;
  final String? direccion;
  // Opcional: ubicación y texto del origen para poder mostrar ambos marcadores
  final LatLng? origenLocation;
  final String? origenDireccion;

  const MapaPreviewView({super.key, required this.location, this.direccion, this.origenLocation, this.origenDireccion});

  @override
  State<MapaPreviewView> createState() => _MapaPreviewViewState();
}

class _MapaPreviewViewState extends State<MapaPreviewView> {
  late MapapreviewViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = MapapreviewViewModel.forSelection(
      initialLocation: widget.location,
      initialDireccion: widget.direccion,
      origenLocation: widget.origenLocation,
      origenDireccion: widget.origenDireccion,
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    // Controller not needed for this preview view; keep method as a no-op
  }

  void _onCameraMove(CameraPosition position) {
    _vm.updateCameraCenter(position.target);
  }

  void _onCameraIdle() {
    // Cuando la cámara queda inactiva, obtener la dirección legible
    _vm.reverseGeocodeCenter();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MapapreviewViewModel>.value(
      value: _vm,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mapa del destino'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Consumer<MapapreviewViewModel>(
            builder: (context, vm, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          
              // Map con tamaño fijo para evitar que se expanda
              SizedBox(
                height: 420,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AppGoogleMap(
                        initialTarget: widget.location,
                        initialZoom: 16,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        onMapCreated: _onMapCreated,
                        onCameraMove: _onCameraMove,
                        onCameraIdle: _onCameraIdle,
                      ),
                    ),

                    // Fixed center marker (overlay)
                    const IgnorePointer(
                      child: Icon(
                        Icons.place,
                        size: 48,
                        color: Color(0xFFFFCA44),
                      ),
                    ),
                  ],
                ),
              ),

              // Contenido inferior desplazable
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // Nombre del lugar en negrilla alineado a la izquierda (mismo padding horizontal)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          vm.formatAddress(
                            widget.direccion ?? 'Nombre del lugar',
                          ),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Dirección legible (ocupa el ancho disponible) — mismo padding horizontal que el texto
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12.0),
                        child: Text(
                          // Mostrar la dirección formateada o las coordenadas si no hay dirección
                          vm.formatAddress(vm.currentAddress).isNotEmpty
                              ? vm.formatAddress(vm.currentAddress)
                              : '${vm.center.latitude.toStringAsFixed(6)}, ${vm.center.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          'Selecciona un destino de la lista o mueve el indicador en el mapa',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 12.0),
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
                onPressed: () async {
                    // Cerrar teclado primero
                    FocusScope.of(context).unfocus();
                    // Capturar el Navigator antes de la brecha async para no usar `context` después
                    final navigator = Navigator.of(context);
                    // Esperar un breve tiempo para asegurar que el teclado se cierre antes de navegar
                    await Future.delayed(
                      const Duration(milliseconds: 120),
                    );

                    // Evitar usar `context` a través de la brecha asíncrona
                    if (!mounted) return;
                    if (!context.mounted) return;

                  // Construir LocationModel para origen y destino y abrir la vista de dos marcadores
                  final origenPos =
                      widget.origenLocation ?? widget.location;
                  final origenTitle = (widget.origenDireccion != null &&
                          widget.origenDireccion!.isNotEmpty)
                      ? _vm.formatAddress(widget.origenDireccion)
                      : 'Origen';
                  final destinoTitle = _vm
                          .formatAddress(_vm.currentAddress)
                          .isNotEmpty
                      ? _vm.formatAddress(_vm.currentAddress)
                      : _vm
                              .formatAddress(widget.direccion)
                              .isNotEmpty
                          ? _vm.formatAddress(widget.direccion)
                          : 'Destino';

                  final origenModel = LocationModel(
                    position: origenPos,
                    title: origenTitle,
                    subtitle: widget.origenDireccion,
                  );
                  final destinoModel = LocationModel(
                    position: _vm.center,
                    title: destinoTitle,
                    subtitle: _vm.currentAddress ?? widget.direccion,
                  );

                    await navigator.push(
                      MaterialPageRoute(
                        builder: (_) => MapPreview(
                          origen: origenModel,
                          destino: destinoModel,
                        ),
                      ),
                    );
                },
                child: const Text(
                  'Definir destino',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
