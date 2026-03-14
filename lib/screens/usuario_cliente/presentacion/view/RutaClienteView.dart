import 'dart:async';
import 'dart:math' as Math;


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteDestinoView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteDestinoViewModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/widgets/LoaderCancelado.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/universal_chat_widget.dart';
import 'package:taxi_app/core/app_colores.dart';




class RutaCliente extends StatefulWidget {
 final String idSolicitud;
 const RutaCliente({Key? key, required this.idSolicitud}) : super(key: key);


 @override
 State<RutaCliente> createState() => _RutaClienteState();
}


class _RutaClienteState extends State<RutaCliente> with WidgetsBindingObserver {


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


   String? _tiempoEstimadoTexto;
   LatLng? _conductorLatLng;
   double? _distanciaMetros;
   List<LatLng> _polyline = [];
   StreamSubscription<String?>? _estadoSolicitudSub;
   Timer? _animacionMarcadorTimer;
   GoogleMapController? _mapController;




 @override
 void initState() {
   super.initState();
   WidgetsBinding.instance.addObserver(this);
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
     vm.inicializarNotificaciones();
     await vm.mostrarNotificacion(
       'Conductor asignado',
       'Vendrá pronto a recogerte.',
     );
     vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
     vm.iniciarChat(widget.idSolicitud);
     // Escuchar estado de la solicitud
       _estadoSolicitudSub = vm.escucharEstadoSolicitudStream(widget.idSolicitud).listen((estado) {
         // debugPrint('[RutaClienteView] Estado de la solicitud actualizado: $estado');
         if (estado == 'cancelado') {
           if (mounted) {
             Navigator.of(context).pushAndRemoveUntil(
               MaterialPageRoute(builder: (context) => InicioClienteView()),
               (route) => false,
             );
           }
         } else if (estado == 'en camino') {
           if (mounted) {
             Navigator.of(context).pushReplacement(
               MaterialPageRoute(
                 builder: (context) => ChangeNotifierProvider(
                   create: (_) => Rutaclientedestinoviewmodel(),
                   child: RutaClienteDestino(idSolicitud: widget.idSolicitud),
                 ),
               ),
             );
           }
         }
       });
     // Escuchar ubicación del conductor desde el ViewModel
     vm.escucharUbicacionConductor(widget.idSolicitud);
     vm.addListener(() async {
       LatLng? conductorLatLng =
           (vm.latConductor != null && vm.lngConductor != null)
           ? LatLng(vm.latConductor!, vm.lngConductor!)
           : null;
       if (conductorLatLng != null) {
         debugPrint('[RutaClienteView] Moviendo marcador del conductor a: \\${conductorLatLng.latitude}, \\${conductorLatLng.longitude}');
       }
       // Mover el marcador del conductor en el mapa
       if (mounted) {
         setState(() {
           _conductorLatLng = conductorLatLng;
         });
       }
       if (_mapController != null) {
         LatLng? clienteLatLng =
             (vm.latCliente != null && vm.lngCliente != null)
             ? LatLng(vm.latCliente!, vm.lngCliente!)
             : null;
         // Obtener polyline, distancia y tiempo estimado
         List<LatLng> polyline = await vm.obtenerPolylineClienteConductor();
         double? distancia;
         String? tiempoTexto;
         if (polyline.isNotEmpty) {
           distancia = vm.calcularDistanciaPolyline(polyline);
           final tiempo = await vm.calcularTiempoEstimado();
           if (tiempo == null || tiempo == -1) {
             tiempoTexto = '-';
           } else {
             final min = (tiempo / 60).ceil();
             tiempoTexto = '$min min';
           }
         } else {
           tiempoTexto = '-';
         }
         if (mounted) {
           setState(() {
             _polyline = polyline;
             _distanciaMetros = distancia;
             _tiempoEstimadoTexto = tiempoTexto;
           });
         }
         // Centrar el mapa automáticamente y adaptar el zoom cuando ambas ubicaciones estén disponibles
         if (_mapController != null && clienteLatLng != null && conductorLatLng != null) {
           // Calcular el centro entre cliente y conductor
           final centerLat = (clienteLatLng.latitude + conductorLatLng.latitude) / 2;
           final centerLng = (clienteLatLng.longitude + conductorLatLng.longitude) / 2;
           // Calcular el ángulo de orientación desde el cliente hacia el conductor
           final dy = conductorLatLng.latitude - clienteLatLng.latitude;
           final dx = conductorLatLng.longitude - clienteLatLng.longitude;
           final bearing = (Math.atan2(dx, dy) * 180 / Math.pi + 360) % 360;
           // Calcular la distancia entre los dos puntos
           final distanceMeters = _calculateDistance(
             clienteLatLng.latitude, clienteLatLng.longitude,
             conductorLatLng.latitude, conductorLatLng.longitude,
           );
           final zoom = _getZoomLevel(distanceMeters);
           // Esperar un pequeño delay para asegurar que el mapa está listo
           await Future.delayed(const Duration(milliseconds: 300));
           if (mounted && _mapController != null) {
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
       }
     });
   });
 }


 @override
 void dispose() {
   WidgetsBinding.instance.removeObserver(this);
   _animacionMarcadorTimer?.cancel();
   _estadoSolicitudSub?.cancel();
   // Si tienes listeners o timers adicionales, cancelarlos aquí
   super.dispose();
 }


 @override
 void didChangeAppLifecycleState(AppLifecycleState state) {
   super.didChangeAppLifecycleState(state);
   if (state == AppLifecycleState.resumed) {
     // Al volver a la app, solo actualizar la posición del marcador del conductor
     final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
     vm.cargarDatosConductorYUbicacionCliente(widget.idSolicitud);
     // Si hay nueva ubicación, solo mover el marcador
     LatLng? nuevaLatLng = (vm.latConductor != null && vm.lngConductor != null)
         ? LatLng(vm.latConductor!, vm.lngConductor!)
         : null;
     if (nuevaLatLng != null) {
       setState(() {
         _conductorLatLng = nuevaLatLng;
       });
     }
   }
 }


 @override
 Widget build(BuildContext context) {
   // Cambiar a variable de estado para alternar entre vistas
   bool mostrarSoloCliente = false;
   final mediaQuery = MediaQuery.of(context);
   final statusBarHeight = mediaQuery.padding.top;
   final size = mediaQuery.size;
   final double screenW = size.width;
   final bool isTablet = screenW >= 1000;
   LatLng? clienteLatLng;
   LatLng? conductorLatLng;
   final vm = Provider.of<Rutaclienteviewmodel>(context);
   clienteLatLng = (vm.latCliente != null && vm.lngCliente != null)
       ? LatLng(vm.latCliente!, vm.lngCliente!)
       : null;
   conductorLatLng = _conductorLatLng ?? ((vm.latConductor != null && vm.lngConductor != null)
       ? LatLng(vm.latConductor!, vm.lngConductor!)
       : null);
   final markers = <Marker>{
     if (mostrarSoloCliente && clienteLatLng != null)
       // ignore: dead_code
       Marker(
         markerId: const MarkerId('cliente'),
         position: clienteLatLng,
         infoWindow: const InfoWindow(title: 'Cliente'),
         icon: BitmapDescriptor.defaultMarkerWithHue(
           BitmapDescriptor.hueGreen,
         ),
       ),
     if (!mostrarSoloCliente && conductorLatLng != null)
       Marker(
         markerId: const MarkerId('conductor'),
         position: conductorLatLng,
         infoWindow: const InfoWindow(title: 'Conductor'),
         icon: BitmapDescriptor.defaultMarkerWithHue(
           BitmapDescriptor.hueAzure,
         ),
       ),
     if (!mostrarSoloCliente && clienteLatLng != null)
       Marker(
         markerId: const MarkerId('cliente'),
         position: clienteLatLng,
         infoWindow: const InfoWindow(title: 'Cliente'),
         icon: BitmapDescriptor.defaultMarkerWithHue(
           BitmapDescriptor.hueGreen,
         ),
       ),
   };


   // --- NUEVO RETURN PRINCIPAL ---
   return WillPopScope(
     onWillPop: () async => false,
     child: AnnotatedRegion<SystemUiOverlayStyle>(
       value: SystemUiOverlayStyle(
         statusBarColor: Colors.transparent,
         statusBarIconBrightness: Brightness.dark,
       ),
       child: MediaQuery.removePadding(
         context: context,
         removeTop: true,
         child: Scaffold(
           backgroundColor: Colors.white,
           resizeToAvoidBottomInset: false,
           body: Column(
             children: [
               // Mapa ocupa el espacio disponible
               Expanded(
                 child: Stack(
                   children: [
                     Mapagoogle(
                       initialTarget: conductorLatLng ?? clienteLatLng ?? const LatLng(8.2595534, -73.353469),
                       initialZoom: 15.0,
                       markers: markers,
                       polylines: _polyline.isNotEmpty
                           ? {
                               Polyline(
                                 polylineId: const PolylineId('ruta'),
                                 points: _polyline,
                                 color: AppColores.buttonPrimary,
                                 width: 5,
                               ),
                             }
                           : {},
                       circles: {},
                       onMapCreated: (controller) => _mapController = controller,
                     ),
                     if (_tiempoEstimadoTexto != null || _distanciaMetros != null)
                       Positioned(
                         top: 55,
                         left: 0,
                         right: 0,
                         child: Center(
                           child: Container(
                             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                             decoration: BoxDecoration(
                               color: Colors.white,
                               borderRadius: BorderRadius.circular(16),
                               boxShadow: [
                                 BoxShadow(
                                   color: Colors.black.withOpacity(0.12),
                                   blurRadius: 8,
                                   offset: const Offset(0, 2),
                                 ),
                               ],
                             ),
                             child: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 if (_tiempoEstimadoTexto != null) ...[
                                   const Icon(Icons.timer, color: AppColores.primary),
                                   const SizedBox(width: 8),
                                   Text(
                                     '$_tiempoEstimadoTexto',
                                     style: const TextStyle(
                                       color: AppColores.textPrimary,
                                       fontWeight: FontWeight.bold,
                                       fontSize: 18,
                                     ),
                                   ),
                                 ],
                                 if (_distanciaMetros != null) ...[
                                   if (_tiempoEstimadoTexto != null) const SizedBox(width: 16),
                                   const Icon(Icons.route, color: AppColores.primary),
                                   const SizedBox(width: 8),
                                   Text(
                                     '${(_distanciaMetros! / 1000).toStringAsFixed(2)} km',
                                     style: const TextStyle(
                                       color: AppColores.textPrimary,
                                       fontWeight: FontWeight.bold,
                                       fontSize: 18,
                                     ),
                                   ),
                                 ],
                               ],
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
         ),
       ),
     );
     


    
 }


 // Mosstrar información del conductor y vehículo en un card debajo del mapa
 Widget _infoRow() {
   final vm = Provider.of<Rutaclienteviewmodel>(context);
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
               // Mostrar foto del vehículo y debajo la placa
               if (vm.fotoVehiculo.isNotEmpty || vm.placaVehiculo.isNotEmpty)
                 Column(
                   children: [
                     if (vm.fotoVehiculo.isNotEmpty)
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


   // Botones de chat y cancelar
   Widget _bottomButtons() {
     final vm = Provider.of<Rutaclienteviewmodel>(context);
     int mensajesPendientes = vm.mensajesPendientes;
     final double screenW = MediaQuery.of(context).size.width;
     final bool isTablet = screenW >= 1000;
     final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
     final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
     final double buttonFontSize = isTablet ? 22 : screenW < 350 ? 13 : 18;
     final double buttonIconSize = isTablet ? 32 : screenW < 350 ? 18 : 24;
     final double buttonBorderRadius = isTablet ? 24 : screenW < 350 ? 8 : 12;
     final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 16;
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
             child: ChatButton(
               mensajesPendientes: mensajesPendientes,
               buttonIconSize: buttonIconSize,
               buttonFontSize: buttonFontSize,
               spacing: spacing,
               isTablet: isTablet,
               solicitudId: widget.idSolicitud,
             ),
           ),
           SizedBox(width: spacing),
           Expanded(
             child: CancelButton(
               buttonIconSize: buttonIconSize,
               buttonFontSize: buttonFontSize,
               buttonBorderRadius: buttonBorderRadius,
               paddingV: paddingV,
               solicitudId: widget.idSolicitud,
             ),
           ),
         ],
       ),
     );
   }


 }


class ChatButton extends StatefulWidget {
   final int mensajesPendientes;
   final double buttonIconSize;
   final double buttonFontSize;
   final double spacing;
   final bool isTablet;
   final String solicitudId;
   const ChatButton({
     required this.mensajesPendientes,
     required this.buttonIconSize,
     required this.buttonFontSize,
     required this.spacing,
     required this.isTablet,
     required this.solicitudId,
   });


   @override
   State<ChatButton> createState() => _ChatButtonState();
 }


class _ChatButtonState extends State<ChatButton> {
   bool chatAbierto = false;
   bool dialogMostrado = false;


   void limpiarMensajesPendientes(BuildContext context) async {
     final vm = Provider.of<Rutaclienteviewmodel>(context, listen: false);
     final usuarioId = vm.usuarioId;
     for (final m in vm.mensajes) {
       if (usuarioId != null &&
           m.senderId != usuarioId &&
           !(m.readBy[usuarioId] ?? false)) {
         await vm.chatService.markMessageRead(
           solicitudId: widget.solicitudId,
           messageId: m.id,
           userId: usuarioId,
         );
       }
     }
   }


   @override
   Widget build(BuildContext context) {
     return Stack(
       clipBehavior: Clip.none,
       children: [
         SizedBox(
           height: widget.isTablet ? 70 : widget.spacing < 8 ? 40 : 56,
           child: OutlinedButton(
             style: OutlinedButton.styleFrom(
               side: BorderSide(
                 color: AppColores.primary,
                 width: 2.5,
               ),
               backgroundColor: Colors.white,
               padding: const EdgeInsets.symmetric(
                 horizontal: 12,
                 vertical: 0,
               ),
               shape: RoundedRectangleBorder(
                 borderRadius: BorderRadius.circular(16),
               ),
             ),
             onPressed: () {
               if (chatAbierto || dialogMostrado) return;
               setState(() {
                 chatAbierto = true;
                 dialogMostrado = true;
               });
               limpiarMensajesPendientes(context);
               showDialog(
                 context: context,
                 barrierDismissible: false,
                 builder: (context) {
                   return Dialog(
                     insetPadding: EdgeInsets.zero,
                     backgroundColor: Colors.transparent,
                     child: SafeArea(
                       child: Container(
                         width: double.infinity,
                         height: MediaQuery.of(context).size.height,
                         color: Colors.white,
                         child: UniversalChatWidget(
                           solicitudId: widget.solicitudId,
                           chatTitle: 'Chat con el conductor',
                           backgroundColor: Colors.white,
                           myMessageColor: AppColores.primary,
                           otherMessageColor: Colors.grey.shade200,
                           sendButtonColor: AppColores.primary,
                           autoFocus: true,
                         ),
                       ),
                     ),
                   );
                 },
               ).then((_) {
                 setState(() {
                   chatAbierto = false;
                   dialogMostrado = false;
                 });
               });
             },
             child: Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 Icon(
                   Icons.chat,
                   color: AppColores.primary,
                   size: widget.buttonIconSize,
                 ),
                 SizedBox(width: widget.spacing / 2),
                 Text(
                   'Chat',
                   style: TextStyle(
                     color: AppColores.primary,
                     fontWeight: FontWeight.w600,
                     fontSize: widget.buttonFontSize,
                   ),
                 ),
               ],
             ),
           ),
         ),
         if (widget.mensajesPendientes > 0)
           Positioned(
             right: 0,
             top: widget.isTablet ? -12 : widget.spacing < 8 ? -4 : -8,
             child: Container(
               padding: EdgeInsets.all(widget.isTablet ? 10 : widget.spacing < 8 ? 3 : 6),
               decoration: BoxDecoration(
                 color: Colors.red,
                 shape: BoxShape.circle,
                 border: Border.all(color: Colors.white, width: widget.isTablet ? 3 : 2),
               ),
               constraints: BoxConstraints(
                 minWidth: widget.isTablet ? 36 : widget.spacing < 8 ? 14 : 24,
                 minHeight: widget.isTablet ? 36 : widget.spacing < 8 ? 14 : 24,
               ),
               child: Center(
                 child: Text(
                   widget.mensajesPendientes.toString(),
                   style: TextStyle(
                     color: Colors.white,
                     fontWeight: FontWeight.bold,
                     fontSize: widget.isTablet ? 22 : widget.spacing < 8 ? 8 : 14,
                   ),
                 ),
               ),
             ),
           ),
       ],
     );
   }
 }


class CancelButton extends StatelessWidget {
   final double buttonIconSize;
   final double buttonFontSize;
   final double buttonBorderRadius;
   final double paddingV;
   final String solicitudId;
   const CancelButton({
     required this.buttonIconSize,
     required this.buttonFontSize,
     required this.buttonBorderRadius,
     required this.paddingV,
     required this.solicitudId,
   });


   @override
   Widget build(BuildContext context) {
     final vm = Provider.of<Rutaclienteviewmodel>(context);
     return ElevatedButton.icon(
       icon: Icon(Icons.cancel, color: Colors.white, size: buttonIconSize),
       label: Text(
         'Cancelar',
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
         await vm.cancelarSolicitud(solicitudId);
         if (!context.mounted) return;
         showDialog(
           context: context,
           barrierDismissible: false,
           builder: (_) => const LoaderSolicitudCancelada(),
         );
         await Future.delayed(const Duration(seconds: 2));
         // Eliminar la solicitud de Firestore
         try {
           await FirebaseFirestore.instance
             .collection('solicitudes')
             .doc(solicitudId)
             .delete();
         } catch (e) {
           debugPrint('Error eliminando solicitud cancelada: $e');
         }
         await Future.delayed(const Duration(seconds: 1));
         if (!context.mounted) return;
         Navigator.of(context).pop(); // Cierra el loader
         Navigator.of(context).pushAndRemoveUntil(
           MaterialPageRoute(builder: (context) => InicioClienteView()),
           (route) => false,
         );
       },
     );
   }
 }


class _MapWidget extends StatelessWidget {
 final Set<Marker> markers;
 final LatLng? conductorLatLng;
 final LatLng? clienteLatLng;
 final Function(GoogleMapController) mapControllerSetter;
 const _MapWidget({
   required this.markers,
   required this.conductorLatLng,
   required this.clienteLatLng,
   required this.mapControllerSetter,
 });


 @override
 Widget build(BuildContext context) {
   final LatLng initialTarget = _getInitialTarget();
  
   return Stack(
     children: [
       Mapagoogle(
         initialTarget: initialTarget,
         initialZoom: 15.0,
         markers: markers,
         //polylines: polylines,
         circles: {},
         //myLocationEnabled: true,
         onMapCreated: (controller) {
           mapControllerSetter(controller);
           _animateCameraToBounds(controller);
         },
       ),
       _CenterConductorButton(
         conductorLatLng: conductorLatLng,
         clienteLatLng: clienteLatLng,
       ),
     ],
   );
 }


 LatLng _getInitialTarget() {
   if (conductorLatLng != null && clienteLatLng != null) {
     return LatLng(
       (conductorLatLng!.latitude + clienteLatLng!.latitude) / 2,
       (conductorLatLng!.longitude + clienteLatLng!.longitude) / 2,
     );
   }
   return conductorLatLng ?? clienteLatLng ?? const LatLng(8.2595534, -73.353469);
 }


 void _animateCameraToBounds(GoogleMapController controller) {
   if (conductorLatLng != null && clienteLatLng != null) {
     final bounds = LatLngBounds(
       southwest: LatLng(
         conductorLatLng!.latitude < clienteLatLng!.latitude
             ? conductorLatLng!.latitude
             : clienteLatLng!.latitude,
         conductorLatLng!.longitude < clienteLatLng!.longitude
             ? conductorLatLng!.longitude
             : clienteLatLng!.longitude,
       ),
       northeast: LatLng(
         conductorLatLng!.latitude > clienteLatLng!.latitude
             ? conductorLatLng!.latitude
             : clienteLatLng!.latitude,
         conductorLatLng!.longitude > clienteLatLng!.longitude
             ? conductorLatLng!.longitude
             : clienteLatLng!.longitude,
       ),
     );
     Future.delayed(const Duration(milliseconds: 300), () {
       controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
     });
   }
 }
}


class _CenterConductorButton extends StatelessWidget {
 final LatLng? conductorLatLng;
 final LatLng? clienteLatLng;
 const _CenterConductorButton({
   required this.conductorLatLng,
   required this.clienteLatLng,
 });


 @override
 Widget build(BuildContext context) {
   return Positioned(
     bottom: 16,
     right: 16,
     child: FloatingActionButton(
       heroTag: 'fab_centrar_conductor',
       backgroundColor: AppColores.primary,
       child: const Icon(Icons.person_pin_circle, color: Colors.white),
       onPressed: () {
         final mapState = context.findAncestorStateOfType<_RutaClienteState>();
         final controller = mapState?._mapController;
         if (controller != null && conductorLatLng != null && clienteLatLng != null) {
           LatLngBounds bounds = LatLngBounds(
             southwest: LatLng(
               clienteLatLng!.latitude < conductorLatLng!.latitude ? clienteLatLng!.latitude : conductorLatLng!.latitude,
               clienteLatLng!.longitude < conductorLatLng!.longitude ? clienteLatLng!.longitude : conductorLatLng!.longitude,
             ),
             northeast: LatLng(
               clienteLatLng!.latitude > conductorLatLng!.latitude ? clienteLatLng!.latitude : conductorLatLng!.latitude,
               clienteLatLng!.longitude > conductorLatLng!.longitude ? clienteLatLng!.longitude : conductorLatLng!.longitude,
             ),
           );
           controller.animateCamera(
             CameraUpdate.newLatLngBounds(bounds, 80),
           );
         }
       },
     ),
   );
 }
}
// ignore: unused_element
class _ActionButtonsWidget extends StatelessWidget {
 final Rutaclienteviewmodel vm;
 final String solicitudId;
 final GoogleMapController? mapController;
 final LatLng? clienteLatLng;
 final LatLng? conductorLatLng;
 const _ActionButtonsWidget({
   required this.vm,
   required this.solicitudId,
   required this.mapController,
   required this.clienteLatLng,
   required this.conductorLatLng,
 });


 @override
 Widget build(BuildContext context) {
   final double screenW = MediaQuery.of(context).size.width;
   final bool isTablet = screenW >= 1000;
   final double paddingH = isTablet ? 32 : screenW < 350 ? 6 : 16;
   final double paddingV = isTablet ? 24 : screenW < 350 ? 4 : 8;
   final double buttonFontSize = isTablet ? 22 : screenW < 350 ? 13 : 18;
   final double buttonIconSize = isTablet ? 32 : screenW < 350 ? 18 : 24;
   final double buttonBorderRadius = isTablet ? 24 : screenW < 350 ? 8 : 12;
   final double spacing = isTablet ? 24 : screenW < 350 ? 6 : 16;
   int mensajesPendientes = vm.mensajesPendientes;
   return Padding(
     padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
     child: Row(
       mainAxisAlignment: MainAxisAlignment.center,
       children: [
         Expanded(
           child: ChatButton(
             mensajesPendientes: mensajesPendientes,
             buttonIconSize: buttonIconSize,
             buttonFontSize: buttonFontSize,
             spacing: spacing,
             isTablet: isTablet,
             solicitudId: solicitudId,
           ),
         ),
         SizedBox(width: spacing),
         Expanded(
           child: CancelButton(
             buttonIconSize: buttonIconSize,
             buttonFontSize: buttonFontSize,
             buttonBorderRadius: buttonBorderRadius,
             paddingV: paddingV,
             solicitudId: solicitudId,
           ),
         ),
       ],
     ),
   );
 }
}
