import 'dart:async';
import 'dart:math' as Math;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';


import 'package:taxi_app/core/app_colores.dart';
import 'package:url_launcher/url_launcher.dart';


class RutaClienteDestino extends StatefulWidget {
 final String idSolicitud;
 const RutaClienteDestino({Key? key, required this.idSolicitud})
   : super(key: key);


 @override
 State<RutaClienteDestino> createState() => _RutaClienteDestinoState();
}




class _RutaClienteDestinoState extends State<RutaClienteDestino> with WidgetsBindingObserver {
 LatLng? _conductorLatLng;
 StreamSubscription<LatLng?>? _conductorLocationSub;
 StreamSubscription? _conductorLocationFirestoreSub;
 Timer? _animacionMarcadorTimer;
 GoogleMapController? _mapController;


 Set<Polyline> _polylines = {};
 String _distancia = '';


 Rutaclientedestinoviewmodel? _viewModel;


 @override
 void initState() {
   super.initState();
   WidgetsBinding.instance.addObserver(this);
   _viewModel = Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
   debugPrint('[RutaClienteDestinoView] Escuchando ubicación del conductor para solicitud: ${widget.idSolicitud}');
   _viewModel!.escucharUbicacionConductor(widget.idSolicitud);
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     await SessionHelper.setActiveSolicitud(widget.idSolicitud);
     _viewModel!.inicializarNotificaciones();
     await _viewModel!.mostrarNotificacion(
       'Conductor en marcha',
       'Conductor está en camino al destino. ¡Prepárate para tu viaje!',
     );
     await _viewModel!.cargarDatosConductorYUbicacionDestino(widget.idSolicitud);
     _viewModel!.escucharEstadoSolicitud(widget.idSolicitud, context);
     // Escuchar cambios para actualizar polyline, tiempo y distancia
     _viewModel!.addListener(_actualizarRuta);
     // Llamar una vez al inicio
     _actualizarRuta();
   });
 }


 Future<void> _actualizarRuta() async {
   if (!mounted) return;
   final vm = Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
   final puntos = await vm.obtenerPolylineConductorDestino();
   LatLng? conductorLatLng = (vm.latConductor != null && vm.lngConductor != null)
       ? LatLng(vm.latConductor!, vm.lngConductor!)
       : null;
   LatLng? destinoLatLng = (vm.latDestino != null && vm.lngDestino != null)
       ? LatLng(vm.latDestino!, vm.lngDestino!)
       : null;
   if (!mounted) return;
   if (puntos.isNotEmpty) {
     if (mounted) {
       setState(() {
         _polylines = {
           Polyline(
             polylineId: const PolylineId('ruta'),
             color: AppColores.buttonPrimary,
             width: 6,
             points: puntos,
           ),
         };
       });
     }
     // Calcular distancia y tiempo estimado
     final distanciaMetros = vm.calcularDistanciaPolyline(puntos);
     String distanciaStr = '';
     if (distanciaMetros >= 1000) {
       distanciaStr = (distanciaMetros / 1000).toStringAsFixed(2) + ' km';
     } else {
       distanciaStr = distanciaMetros.toStringAsFixed(0) + ' m';
     }
     if (mounted) {
       setState(() {
         _distancia = distanciaStr;
       });
     }
     // Calcular tiempo estimado y actualizar en el ViewModel
     final segundos = await vm.calcularTiempoEstimado();
     if (segundos != null) {
       final minutos = (segundos / 60).ceil();
       vm.setTiempoEstimado('$minutos min');
     }
     // Centrar ambos marcadores y ajustar perspectiva si existen
     if (_mapController != null && conductorLatLng != null && destinoLatLng != null) {
       // Calcular el centro entre conductor y destino
       final centerLat = (conductorLatLng.latitude + destinoLatLng.latitude) / 2;
       final centerLng = (conductorLatLng.longitude + destinoLatLng.longitude) / 2;
       // Calcular el ángulo de orientación desde el conductor hacia el destino
       final dy = destinoLatLng.latitude - conductorLatLng.latitude;
       final dx = destinoLatLng.longitude - conductorLatLng.longitude;
       final bearing = (Math.atan2(dx, dy) * 180 / Math.pi + 360) % 360;
       // Calcular la distancia en metros entre los dos puntos
       double distanceMeters = _calculateDistance(
         conductorLatLng.latitude, conductorLatLng.longitude,
         destinoLatLng.latitude, destinoLatLng.longitude,
       );
       double zoom = _getZoomLevel(distanceMeters);
       // Definir bounds para centrar ambos marcadores
       final bounds = LatLngBounds(
         southwest: LatLng(
           conductorLatLng.latitude < destinoLatLng.latitude ? conductorLatLng.latitude : destinoLatLng.latitude,
           conductorLatLng.longitude < destinoLatLng.longitude ? conductorLatLng.longitude : destinoLatLng.longitude,
         ),
         northeast: LatLng(
           conductorLatLng.latitude > destinoLatLng.latitude ? conductorLatLng.latitude : destinoLatLng.latitude,
           conductorLatLng.longitude > destinoLatLng.longitude ? conductorLatLng.longitude : destinoLatLng.longitude,
         ),
       );
       await Future.delayed(const Duration(milliseconds: 300));
       if (mounted && _mapController != null) {
         await _mapController!.animateCamera(
           CameraUpdate.newLatLngBounds(bounds, 80),
         );
         await _mapController!.animateCamera(
           CameraUpdate.newCameraPosition(
             CameraPosition(
               target: LatLng(centerLat, centerLng),
               zoom: zoom,
               bearing: bearing,
             ),
           ),
         );
       }
     }


   } else {
     if (mounted) {
       setState(() {
         _polylines = {};
         _distancia = '';
       });
     }
   }
 }






  // Calcula la distancia entre dos coordenadas en metros (Haversine)
 double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
   const R = 6371000; // Radio de la Tierra en metros
   final dLat = (lat2 - lat1) * Math.pi / 180;
   final dLon = (lon2 - lon1) * Math.pi / 180;
   final a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
       Math.cos(lat1 * Math.pi / 180) * Math.cos(lat2 * Math.pi / 180) *
       Math.sin(dLon / 2) * Math.sin(dLon / 2);
   final c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
   return R * c;
 }


 // Devuelve un nivel de zoom adecuado según la distancia en metros
 double _getZoomLevel(double distanceMeters) {
   if (distanceMeters < 200) return 18.0;
   if (distanceMeters < 500) return 17.0;
   if (distanceMeters < 1000) return 16.0;
   if (distanceMeters < 2000) return 15.0;
   if (distanceMeters < 5000) return 14.0;
   if (distanceMeters < 10000) return 13.0;
   if (distanceMeters < 20000) return 12.0;
   return 11.0;
 }


 @override
 void dispose() {
   WidgetsBinding.instance.removeObserver(this);
   _animacionMarcadorTimer?.cancel();
   _conductorLocationSub?.cancel();
   _conductorLocationFirestoreSub?.cancel();
   // Remover listener del ViewModel para evitar llamadas tras dispose
   _viewModel?.removeListener(_actualizarRuta);
   super.dispose();
 }


 @override
 void didChangeAppLifecycleState(AppLifecycleState state) {
   super.didChangeAppLifecycleState(state);
   if (state == AppLifecycleState.resumed) {
     // Al volver a la app, actualizar datos de la solicitud (ubicación del conductor, estado, etc.)
     final vm = Provider.of<Rutaclientedestinoviewmodel>(context, listen: false);
     vm.cargarDatosConductorYUbicacionDestino(widget.idSolicitud);
   }
   // Puedes agregar lógica en onPause si lo necesitas
 }


 @override
 Widget build(BuildContext context) {
   bool mostrarSoloDestino = false;
   return WillPopScope(
     onWillPop: () async => false,
     child: AnnotatedRegion<SystemUiOverlayStyle>(
       value: SystemUiOverlayStyle(
         statusBarColor: Colors.transparent,
         statusBarIconBrightness: Brightness.dark,
       ),
       child: Scaffold(
         backgroundColor: Colors.white,
         resizeToAvoidBottomInset: false,
         body: Consumer<Rutaclientedestinoviewmodel>(
           builder: (context, vm, _) {
             final size = MediaQuery.of(context).size;
             final double screenW = size.width;
             final bool isTablet = screenW >= 1000;
             LatLng? destinoLatLng =
                 (vm.latDestino != null && vm.lngDestino != null)
                 ? LatLng(vm.latDestino!, vm.lngDestino!)
                 : null;
             LatLng? conductorLatLng =
                 _conductorLatLng ??
                 ((vm.latConductor != null && vm.lngConductor != null)
                     ? LatLng(vm.latConductor!, vm.lngConductor!)
                     : null);
             final markers = <Marker>{
               if (mostrarSoloDestino && destinoLatLng != null)
                 Marker(
                   markerId: const MarkerId('destino'),
                   position: destinoLatLng,
                   infoWindow: const InfoWindow(title: 'Destino'),
                   icon: BitmapDescriptor.defaultMarkerWithHue(
                     BitmapDescriptor.hueGreen,
                   ),
                 ),
               if (!mostrarSoloDestino && conductorLatLng != null)
                 Marker(
                   markerId: const MarkerId('conductor'),
                   position: conductorLatLng,
                   infoWindow: const InfoWindow(title: 'Conductor'),
                   icon: BitmapDescriptor.defaultMarkerWithHue(
                     BitmapDescriptor.hueAzure,
                   ),
                 ),
               if (!mostrarSoloDestino && destinoLatLng != null)
                 Marker(
                   markerId: const MarkerId('destino'),
                   position: destinoLatLng,
                   infoWindow: const InfoWindow(title: 'Destino'),
                   icon: BitmapDescriptor.defaultMarkerWithHue(
                     BitmapDescriptor.hueGreen,
                   ),
                 ),
             };
             return Stack(
               children: [
                 SafeArea(
                   child: Column(
                     children: [
                       SizedBox(
                         height: MediaQuery.of(context).size.height * 0.63,
                         child: Stack(
                           children: [
                             _MapWidget(
                               markers: markers,
                               conductorLatLng: conductorLatLng,
                               destinoLatLng: destinoLatLng,
                               mapControllerSetter: (controller) => _mapController = controller,
                               polylines: _polylines,
                             ),
                             Positioned(
                               top: 16,
                               left: 0,
                               right: 0,
                               child: Center(
                                 child: Material(
                                   elevation: 8,
                                   borderRadius: BorderRadius.circular(16),
                                   color: Colors.white,
                                   child: Container(
                                     width: 260,
                                     padding: EdgeInsets.symmetric(
                                       horizontal: 18,
                                       vertical: 16,
                                     ),
                                     decoration: BoxDecoration(
                                       color: Colors.white,
                                       borderRadius: BorderRadius.circular(16),
                                     ),
                                     child: Column(
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                         Row(
                                           mainAxisAlignment: MainAxisAlignment.center,
                                           children: [
                                             Icon(Icons.access_time, color: AppColores.primary, size: 22),
                                             SizedBox(width: 8),
                                             Text(
                                               vm.tiempoEstimado,
                                               style: TextStyle(
                                                 fontWeight: FontWeight.bold,
                                                 fontSize: 16,
                                                 color: AppColores.textSecondary,
                                               ),
                                             ),
                                             SizedBox(width: 16),
                                             Icon(Icons.route, color: AppColores.primary, size: 22),
                                             SizedBox(width: 4),
                                             Text(
                                               _distancia,
                                               style: TextStyle(
                                                 fontWeight: FontWeight.bold,
                                                 fontSize: 16,
                                                 color: AppColores.textSecondary,
                                               ),
                                             ),
                                           ],
                                         ),
                                       ],
                                     ),
                                   ),
                                 ),
                               ),
                             ),
                           ],
                         ),
                       ),
                        // Card ocupa la parte inferior, scrollable y segura
             SafeArea(
               top: false,
               child: SingleChildScrollView(
                 child: Container(
                   width: double.infinity,
                   decoration: BoxDecoration(
                     color: Colors.white,
                     borderRadius: BorderRadius.only(
                       topLeft: Radius.circular(isTablet ? 24 : 16),
                       topRight: Radius.circular(isTablet ? 24 : 16),
                     ),
                     boxShadow: [
                       BoxShadow(
                         color: Colors.black.withOpacity(0.08),
                         blurRadius: 12,
                         offset: const Offset(0, 4),
                       ),
                     ],
                   ),
                   child: Padding(
                     padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 12, vertical: isTablet ? 24 : 12),
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         _infoRow(),
                         SizedBox(height: isTablet ? 12 : 8),
                         _bottomButtons(),
                       ],
                     ),
                   ),
                 ),
               ),
             ),
                     ],
                   ),
                 ),
                 //posicionar el boton de mostrar solo destino/conductor
                 Positioned(
                   bottom: 330,
                   right: 20,
                   child: FloatingActionButton(
                     backgroundColor: AppColores.primary,
                     child: Icon(
                       mostrarSoloDestino
                           ? Icons.flag
                           : Icons.person_pin_circle,
                       color: Colors.white,
                     ),
                     onPressed: () {
                       setState(() {
                         mostrarSoloDestino = !mostrarSoloDestino;
                         if (_mapController != null) {
                           if (mostrarSoloDestino && destinoLatLng != null) {
                             _mapController!.animateCamera(
                               CameraUpdate.newCameraPosition(
                                 CameraPosition(
                                   target: destinoLatLng,
                                   zoom: 16,
                                   tilt: 0,
                                 ),
                               ),
                             );
                           } else if (!mostrarSoloDestino && destinoLatLng != null && conductorLatLng != null) {
                             // Centrar ambos marcadores usando bounds
                             LatLngBounds bounds = LatLngBounds(
                               southwest: LatLng(
                                 destinoLatLng.latitude < conductorLatLng.latitude
                                     ? destinoLatLng.latitude
                                     : conductorLatLng.latitude,
                                 destinoLatLng.longitude < conductorLatLng.longitude
                                     ? destinoLatLng.longitude
                                     : conductorLatLng.longitude,
                               ),
                               northeast: LatLng(
                                 destinoLatLng.latitude > conductorLatLng.latitude
                                     ? destinoLatLng.latitude
                                     : conductorLatLng.latitude,
                                 destinoLatLng.longitude > conductorLatLng.longitude
                                     ? destinoLatLng.longitude
                                     : conductorLatLng.longitude,
                               ),
                             );
                             _mapController!.animateCamera(
                               CameraUpdate.newLatLngBounds(bounds, 80),
                             );
                           }
                         }
                       });
                     },
                   ),
                 ),
               ],
             );
           },
         ),
       ),
     ),
   );
 }




 // Mosstrar información del conductor y vehículo en un card debajo del mapa
 Widget _infoRow() {
   final vm = Provider.of<Rutaclientedestinoviewmodel>(context);
   final size = MediaQuery.of(context).size;
   final double screenW = size.width;
   final bool isTablet = screenW >= 1000;
   final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 12;
   final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
   final double avatarRadius = isTablet ? 60 : screenW < 350 ? 22 : 40;
   final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 12;
   final double nameFontSize = isTablet ? 32 : screenW < 350 ? 12 : 18;
   final double placaFontSize = isTablet ? 22 : screenW < 350 ? 10 : 15;
   final double imageW = isTablet ? 160 : screenW < 350 ? 60 : 100;
   final double imageH = isTablet ? 120 : screenW < 350 ? 40 : 70;
   return Container(
     width: double.infinity,
     padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
     decoration: BoxDecoration(
       color: AppColores.surface,
       borderRadius: BorderRadius.circular(isTablet ? 24 : screenW < 350 ? 8 : 12),
     ),
     child: SingleChildScrollView(
       physics: const NeverScrollableScrollPhysics(),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.stretch,
         children: [
           SizedBox(height: spacing / 2),
           Row(
             crossAxisAlignment: CrossAxisAlignment.center,
             children: [
               Column(
                 children: [
                   Padding(
                     padding: EdgeInsets.all(isTablet ? 12 : screenW < 350 ? 2 : 6),
                     child: CircleAvatar(
                       radius: avatarRadius,
                       backgroundColor: AppColores.primary,
                       backgroundImage: vm.fotoConductor.isNotEmpty
                           ? NetworkImage(vm.fotoConductor)
                           : null,
                       child: vm.fotoConductor.isEmpty
                           ? const Icon(Icons.person, color: Colors.white)
                           : null,
                     ),
                   ),
                   SizedBox(height: spacing / 2),
                   Padding(
                     padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 8, vertical: isTablet ? 6 : 2),
                     child: Text(
                       vm.nombreConductor.isNotEmpty
                           ? vm.nombreConductor
                           : 'Conductor',
                       style: TextStyle(
                         fontSize: nameFontSize,
                         fontWeight: FontWeight.bold,
                       ),
                     ),
                   ),
                 ],
               ),
               SizedBox(
                 width: isTablet ? 48 : screenW < 350 ? 8 : size.width * 0.12,
               ),
               if (vm.fotoVehiculo.isNotEmpty)
                 Column(
                   children: [
                     Padding(
                       padding: EdgeInsets.all(isTablet ? 10 : screenW < 350 ? 2 : 5),
                       child: ClipRRect(
                         borderRadius: BorderRadius.circular(isTablet ? 18 : screenW < 350 ? 6 : 12),
                         child: Image.network(
                           vm.fotoVehiculo,
                           width: imageW,
                           height: imageH,
                           fit: BoxFit.cover,
                         ),
                       ),
                     ),
                     SizedBox(height: spacing / 2),
                     Padding(
                       padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 8, vertical: isTablet ? 6 : 2),
                       child: Text(
                         vm.placaVehiculo.isNotEmpty
                             ? vm.placaVehiculo
                             : 'Placa no disponible',
                         style: TextStyle(
                           fontSize: placaFontSize,
                           color: AppColores.textPrimary,
                           fontWeight: FontWeight.w600,
                         ),
                         textAlign: TextAlign.center,
                       ),
                     ),
                   ],
                 ),
             ],
           ),
         ],
       ),
     ),
   );
 }


 Widget _bottomButtons() {
   final vm = Provider.of<Rutaclientedestinoviewmodel>(context);
   final size = MediaQuery.of(context).size;
   final double screenW = size.width;
   final bool isTablet = screenW >= 1000;
    final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
   final double paddingV = isTablet
       ? 24
       : screenW < 350
       ? 4
       : 8;
   final double buttonFontSize = isTablet
       ? 22
       : screenW < 350
       ? 13
       : 18;
   final double buttonIconSize = isTablet
       ? 32
       : screenW < 350
       ? 18
       : 24;
   final double buttonBorderRadius = isTablet
       ? 24
       : screenW < 350
       ? 8
       : 12;
   final double spacing = isTablet
       ? 24
       : screenW < 350
       ? 6
       : 16;
   return Container(
     padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
     decoration: BoxDecoration(
       color: AppColores.surface,
       borderRadius: BorderRadius.circular(buttonBorderRadius),
     ),
     child: Row(
       mainAxisAlignment: MainAxisAlignment.center,
       children: [
         Expanded(
           child: ElevatedButton.icon(
             icon: Icon(
               Icons.my_location,
               color: Colors.white,
               size: buttonIconSize,
             ),
             label: Text(
                'Ubicación',
               style: TextStyle(
                 color: Colors.white,
                 fontWeight: FontWeight.w600,
                 fontSize: buttonFontSize,
               ),
             ),
             style: ElevatedButton.styleFrom(
               backgroundColor: AppColores.primary,
               padding: EdgeInsets.symmetric(vertical: paddingV * 2),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(buttonBorderRadius),
               ),
             ),
             onPressed: () async {
               final conductorLatLng = _conductorLatLng ??
                   ((vm.latConductor != null && vm.lngConductor != null)
                       ? LatLng(vm.latConductor!, vm.lngConductor!)
                       : null);
               if (conductorLatLng != null) {
                 final url = 'https://www.google.com/maps/search/?api=1&query=${conductorLatLng.latitude},${conductorLatLng.longitude}';
                 await Clipboard.setData(ClipboardData(text: url));
                 showModalBottomSheet(
                   context: context,
                   isScrollControlled: true,
                   backgroundColor: Colors.white,
                   shape: RoundedRectangleBorder(
                     borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                   ),
                   builder: (context) {
                     return Container(
                       height: MediaQuery.of(context).size.height * 0.5,
                       padding: EdgeInsets.all(24),
                       child: Column(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           Text('Compartir ubicación',
                             style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                           SizedBox(height: 32),
                           ElevatedButton.icon(
                             icon: Icon(Icons.map, color: Colors.white),
                             label: Text('Google Maps'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: AppColores.primary,
                               minimumSize: Size(double.infinity, 48),
                             ),
                             onPressed: () async {
                               await launchUrl(Uri.parse(url));
                             },
                           ),
                           SizedBox(height: 16),
                           ElevatedButton.icon(
                             icon: Icon(Icons.chat, color: Colors.white),
                             label: Text('WhatsApp'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.green,
                               minimumSize: Size(double.infinity, 48),
                             ),
                             onPressed: () async {
                               final whatsappUrl = 'https://wa.me/?text=Ubicación%20del%20conductor:%20$url';
                               if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                                 await launchUrl(Uri.parse(whatsappUrl));
                               } else {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   SnackBar(
                                     content: Text('No se pudo abrir WhatsApp'),
                                     duration: Duration(seconds: 3),
                                   ),
                                 );
                               }
                             },
                           ),
                         ],
                       ),
                     );
                   },
                 );
               } else {
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                     content: Text('Ubicación no disponible'),
                     duration: Duration(seconds: 3),
                   ),
                 );
               }
             },
           ),
         ),
         SizedBox(width: spacing),
         Expanded(
           child: ElevatedButton.icon(
             icon: Icon(Icons.info, color: Colors.white, size: buttonIconSize),
             label: Text(
               'Estado',
               style: TextStyle(
                 color: Colors.white,
                 fontWeight: FontWeight.w600,
                 fontSize: buttonFontSize,
               ),
             ),
             style: ElevatedButton.styleFrom(
               backgroundColor: AppColores.primary,
               padding: EdgeInsets.symmetric(vertical: paddingV * 2),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(buttonBorderRadius),
               ),
             ),
             onPressed: () {
               final estado = vm.estado;
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Estado actual: $estado')),
               );
             },
           ),
         ),
       ],
     ),
   );
  }
}




class _MapWidget extends StatelessWidget {
 final Set<Marker> markers;
 final LatLng? conductorLatLng;
 final LatLng? destinoLatLng;
 final Function(GoogleMapController) mapControllerSetter;
 final Set<Polyline> polylines;
 const _MapWidget({
   required this.markers,
   required this.conductorLatLng,
   required this.destinoLatLng,
   required this.mapControllerSetter,
   required this.polylines,
 });


 @override
 Widget build(BuildContext context) {
   LatLng initialTarget;
   if (conductorLatLng != null && destinoLatLng != null) {
     initialTarget = LatLng(
       (conductorLatLng!.latitude + destinoLatLng!.latitude) / 2,
       (conductorLatLng!.longitude + destinoLatLng!.longitude) / 2,
     );
   } else {
     initialTarget =
         conductorLatLng ??
         destinoLatLng ??
         const LatLng(8.2595534, -73.353469);
   }
   return Stack(
     children: [
       Mapagoogle(
         initialTarget: initialTarget,
         initialZoom: 15.0,
         markers: markers,
         polylines: polylines,
         onMapCreated: (controller) {
           mapControllerSetter(controller);
           if (conductorLatLng != null && destinoLatLng != null) {
             final bounds = LatLngBounds(
               southwest: LatLng(
                 conductorLatLng!.latitude < destinoLatLng!.latitude
                     ? conductorLatLng!.latitude
                     : destinoLatLng!.latitude,
                 conductorLatLng!.longitude < destinoLatLng!.longitude
                     ? conductorLatLng!.longitude
                     : destinoLatLng!.longitude,
               ),
               northeast: LatLng(
                 conductorLatLng!.latitude > destinoLatLng!.latitude
                     ? conductorLatLng!.latitude
                     : destinoLatLng!.latitude,
                 conductorLatLng!.longitude > destinoLatLng!.longitude
                     ? conductorLatLng!.longitude
                     : destinoLatLng!.longitude,
               ),
             );
             Future.delayed(const Duration(milliseconds: 300), () {
               controller.animateCamera(
                 CameraUpdate.newLatLngBounds(bounds, 80),
               );
             });
           }
         },
       ),
     ],
   );
 }
}
