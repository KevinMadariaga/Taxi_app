import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/responsive_helper.dart';

import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/mapapreview_viewmodel.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';

import 'seleccion_destino_view.dart';
import 'package:taxi_app/core/app_colores.dart';


class MapPreview extends StatefulWidget {
  final LocationModel origen;
  final LocationModel destino;

  const MapPreview({super.key, required this.origen, required this.destino});

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> {
  GoogleMapController? _controller;
  late MapapreviewViewModel _vm;
  BitmapDescriptor? _destIcon;
  VoidCallback? _vmListener;

  @override
  void initState() {
    super.initState();
    _vm = MapapreviewViewModel(
      origen: widget.origen,
      destino: widget.destino,
    );
    _vm.init();
    // Refit camera when ViewModel updates (e.g., polylines are ready)
    _vmListener = () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBoundsToMarkers();
      });
    };
    _vm.addListener(_vmListener!);
    _loadDestIcon();
  }

  Future<void> _loadDestIcon() async {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() {
        _destIcon = icon;
      });
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    // Ajustar cámara para que ambos marcadores sean visibles
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBoundsToMarkers();
    });
  }

  Future<void> _fitBoundsToMarkers() async {
    if (_controller == null) return;
    final bounds = _vm.cameraBounds;
    if (bounds == null) return;
    try {
      // Increase padding so the full polyline and both markers are comfortably visible
      await _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 120),
      );
    } catch (_) {
      // Si falla (por ejemplo mapa no ha renderizado), intentar de nuevo levemente después
      await Future.delayed(const Duration(milliseconds: 200));
      try {
        await _controller!
            .animateCamera(CameraUpdate.newLatLngBounds(bounds, 120));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (_vmListener != null) _vm.removeListener(_vmListener!);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MapapreviewViewModel>.value(
      value: _vm,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
              // Map con tamaño responsive para evitar estiramiento
              SizedBox(
                height: ResponsiveHelper.hp(context, 45),
                child: Consumer<MapapreviewViewModel>(
                  builder: (context, vm, _) {
                    final origen = vm.origen.position;
                    final destino = vm.destino.position;

                    return ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(ResponsiveHelper.wp(context, 4)),
                        bottomRight: Radius.circular(ResponsiveHelper.wp(context, 4)),
                      ),
                      child: AppGoogleMap(
                        initialTarget: LatLng(
                          (origen.latitude + destino.latitude) / 2,
                          (origen.longitude + destino.longitude) / 2,
                        ),
                        initialZoom: 13,
                        onMapCreated: _onMapCreated,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        markers: {
                        Marker(
                          markerId: const MarkerId('ubicacion'),
                          position: origen,
                          infoWindow: InfoWindow(title: vm.origen.title ?? 'Ubicación', snippet: vm.origen.subtitle),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                        ),
                        Marker(
                          markerId: const MarkerId('destino'),
                          position: destino,
                          infoWindow: InfoWindow(title: vm.destino.title ?? 'Destino', snippet: vm.destino.subtitle),
                          icon: _destIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                      },
                        polylines: vm.polylines,
                      ),
                    );
                  },
                ),
              ),

              // Datos debajo del mapa (tarjetas y acciones)
              Expanded(
                child: SingleChildScrollView(
                  child: Consumer<MapapreviewViewModel>(builder: (context, vm, _) {
                    return Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.wp(context, 4)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      // Origen card
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 4)),
                          border: Border.all(color: Colores.amarillo, width: 1.5),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 5)), border: Border.all(color: Colores.amarillo)),
                              child: const Icon(Icons.location_on_outlined, color: Colors.black54),
                            ),
                            SizedBox(width: ResponsiveHelper.wp(context, 3)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Tu ubicación actual', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 12), color: Colors.black54)),
                                  SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                                  Text(
                                    vm.origen.title ?? 'Ubicación',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: ResponsiveHelper.sp(context, 14)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.hp(context, 1)),

                      // Destino card
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 3)),
                          border: Border.all(color: Colores.amarillo, width: 1.5),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 5)), border: Border.all(color: Colors.black12)),
                              child: const Icon(Icons.place, color: Colors.black54),
                            ),
                            SizedBox(width: ResponsiveHelper.wp(context, 3)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('¿Adónde va?', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 12), color: Colors.black54)),
                                  SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                                  Text(
                                    vm.destino.title ?? 'Destino',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: ResponsiveHelper.sp(context, 14)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: ResponsiveHelper.hp(context, 1)),

                      // Método de pago
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.wp(context,2)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 3)),
                          border: Border.all(color: Colors.black12),
                          color: Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Método de pago', style: TextStyle(fontWeight: FontWeight.w700, fontSize: ResponsiveHelper.sp(context, 14))),
                            SizedBox(height: ResponsiveHelper.hp(context, 1)),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => vm.setMetodoPago('Efectivo'),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.8)),
                                      decoration: BoxDecoration(
                                        color: vm.metodoPago == 'Efectivo' ? Colores.amarillo : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 6)),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Efectivo', style: TextStyle(fontWeight: FontWeight.w700,color: vm.metodoPago == 'Efectivo' ? Colors.black87 : Colors.black54, fontSize: ResponsiveHelper.sp(context, 14))),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => vm.setMetodoPago('Transferencia'),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.8)),
                                      decoration: BoxDecoration(
                                        color: vm.metodoPago == 'Transferencia' ? Colores.amarillo : Colors.grey[200],
                                        borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 6)),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text('Transferencia', style: TextStyle(fontWeight: FontWeight.w700,color: vm.metodoPago == 'Transferencia' ? Colors.black87 : Colors.black54, fontSize: ResponsiveHelper.sp(context, 14))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: ResponsiveHelper.hp(context, 1)),

                      // Valor del servicio
                      Container(
                        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 2), horizontal: ResponsiveHelper.wp(context, 3)),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 2)),
                          border: Border.all(color: Colors.black12),
                        ),
                          child: Text('Valor del servicio: ${vm.valorServicio}', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 16), fontWeight: FontWeight.w700)),
                      ),

                      SizedBox(height: ResponsiveHelper.hp(context, 1)),

                      SizedBox(
                        width: double.infinity,
                        height: ResponsiveHelper.hp(context, 6.5),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colores.amarillo, foregroundColor: Colors.black87, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 2)))),
                          onPressed: vm.isSubmitting
                              ? null
                              : () async {
                                  final navigator = Navigator.of(context);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final solicitudId = await vm.crearSolicitud();
                                  if (!mounted) return;
                                  if (solicitudId != null) {
                                    navigator.push(
                                      MaterialPageRoute(
                                        builder: (_) => BuscandoTaxiView(
                                          solicitudId: solicitudId,
                                        ),
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Error al crear la solicitud',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: vm.isSubmitting
                              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2))
                              : Text('Buscar conductor', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 16), fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                );
                }), 
                ),
              ),
              ],
              ),

              // Botón sobre el mapa (esquina superior izquierda)
              Positioned(
                left: ResponsiveHelper.wp(context, 3),
                top: ResponsiveHelper.hp(context, 2),
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      // Navegar a la pantalla de selección de destino
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DestinoSeleccionView(currentLocation: widget.origen.position),
                      ));
                    },
                    child: Padding(
                      padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
                      child: Icon(Icons.arrow_back, color: Colors.black87, size: ResponsiveHelper.sp(context, 20)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
                     
