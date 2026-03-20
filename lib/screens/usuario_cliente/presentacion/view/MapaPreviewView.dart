
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/DetailsSolicitud.dart';

import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/mapapreview_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';


/// Vista para seleccionar el destino en el mapa.
/// Permite al usuario mover el marcador y confirmar la ubicación de destino.
class MapaPreviewView extends StatefulWidget {
  final LatLng location;
  final String? direccion;
  final LatLng? origenLocation;
  final String? origenDireccion;

  const MapaPreviewView({
    super.key,
    required this.location,
    this.direccion,
    this.origenLocation,
    this.origenDireccion,
  });

  @override
  State<MapaPreviewView> createState() => _MapaPreviewViewState();
}

class _MapaPreviewViewState extends State<MapaPreviewView> {
  late final MapapreviewViewModel _vm;
  


  /// Widget para el botón inferior.
  Widget _buildBottomBar(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Padding(
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
            onPressed: () => _onDefinirDestinoPressed(context),
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
    );
  }

  /// Lógica para el botón "Definir destino".
  Future<void> _onDefinirDestinoPressed(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted || !context.mounted) return;

    final origenPos = widget.origenLocation ?? widget.location;
    final origenTitle = (widget.origenDireccion != null && widget.origenDireccion!.isNotEmpty)
        ? _vm.formatAddress(widget.origenDireccion)
        : 'Origen';
    final destinoTitle = _vm.formatAddress(_vm.currentAddress).isNotEmpty
        ? _vm.formatAddress(_vm.currentAddress)
        : _vm.formatAddress(widget.direccion).isNotEmpty
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
  }

  @override
  void initState() {
    super.initState();
    _vm = MapapreviewViewModel.forSelection(
      initialLocation: widget.location,
      initialDireccion: widget.direccion,
      origenLocation: widget.origenLocation,
      origenDireccion: widget.origenDireccion,
    );
    // Realiza la geocodificación inversa al iniciar
    _vm.reverseGeocodeCenter();
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double mapHeight = isTablet ? 600 : 420;
    final double maxContentWidth = isTablet ? 900 : double.infinity;
    final double titleFontSize = isTablet ? 22 : 19;
    final double addressTitleFontSize = isTablet ? 26 : 22;
    final double addressSubtitleFontSize = isTablet ? 20 : 18;
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
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 12, vertical: 12),
              child: Consumer<MapapreviewViewModel>(
                builder: (context, vm, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: isTablet ? 20 : 10),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 15),
                      child: Center(
                        child: Text(
                          'Mueve el indicador en el mapa',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isTablet ? 25 : 15),
                    Center(
                      child: SizedBox(
                        height: mapHeight,
                        width: isTablet ? maxContentWidth * 0.9 : double.infinity,
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
                                child: Mapagoogle(
                                  initialTarget: widget.location,
                                  initialZoom: 16,
                                  // myLocationEnabled: false,
                                  // myLocationButtonEnabled: false,
                                  // rotateGesturesEnabled: false,
                                  // tiltGesturesEnabled: false,
                                  // onMapCreated: _onMapCreated,
                                  // onCameraMove: _onCameraMove,
                                  // onCameraIdle: _onCameraIdle,
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: isTablet ? 30 : 20),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 15),
                              child: Text(
                                vm.formatAddress(widget.direccion ?? 'Nombre del lugar').toUpperCase(),
                                style: TextStyle(
                                  fontSize: addressTitleFontSize,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            SizedBox(height: isTablet ? 12 : 8),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 15),
                              child: Text(
                                vm.formatAddress(vm.currentAddress).isNotEmpty
                                    ? vm.formatAddress(vm.currentAddress)
                                    : '${vm.center.latitude.toStringAsFixed(6)}, ${vm.center.longitude.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: addressSubtitleFontSize,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            SizedBox(height: isTablet ? 18 : 12),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }
}
