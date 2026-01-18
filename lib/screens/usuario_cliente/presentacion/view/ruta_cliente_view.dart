import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/chat_message.dart';
import 'package:taxi_app/services/chat_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/map_loading_widget.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ruta_destino_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/ruta_cliente_viewmodel.dart';
import 'package:taxi_app/services/route_cache_service.dart';
import 'package:taxi_app/services/notificacion_servicio.dart';


class RutaClienteView extends StatefulWidget {
  final String solicitudId;
  final String? conductorId;
  final String? conductorName;
  final String? conductorPhone;

  const RutaClienteView({super.key, required this.solicitudId, this.conductorId, this.conductorName, this.conductorPhone});

  @override
  State<RutaClienteView> createState() => _RutaClienteViewState();
}

class _RutaClienteViewState extends State<RutaClienteView> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _taxiIcon;
  BitmapDescriptor? _clientIcon;
  late RutaClienteViewModel _vm;
  final ChatService _chatService = ChatService();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final FocusNode _chatFocusNode = FocusNode();
  bool _isChatOpen = false;
  bool _handledCancelNavigation = false;
  bool _handledDestinoNavigation = false;
  RouteCacheData? _routeCache;
  

  @override
  void initState() {
    super.initState();
    _vm = RutaClienteViewModel(
      solicitudId: widget.solicitudId,
      conductorId: widget.conductorId,
      conductorName: widget.conductorName,
      conductorPhone: widget.conductorPhone,
    );
    _vm.init();
    _loadTaxiIcon();
    _loadClientIcon();
    _restoreCacheAndNotifyCliente();
  }

  
  
  Future<void> _restoreCacheAndNotifyCliente() async {
    try {
      final cache = await RouteCacheService.loadForSolicitud(widget.solicitudId);
      if (!mounted) return;
      if (cache != null) {
        setState(() {
          _routeCache = cache;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await NotificacionesServicio.instance.showTripNotification(
            title: 'Solicitud activa',
            body: 'Continúa el servicio',
          );
        });
      }
    } catch (_) {}
  }
  double _haversineDistanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // metros
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  double _zoomForDistanceMeters(double meters) {
    if (meters < 200) return 18;
    if (meters < 500) return 17;
    if (meters < 1000) return 16;
    if (meters < 2000) return 15;
    if (meters < 5000) return 14;
    if (meters < 10000) return 13;
    return 12;
  }


  @override
  void dispose() {
    _vm.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadTaxiIcon() async {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/taxi_icon.png',
      );
      if (!mounted) return;
      setState(() {
        _taxiIcon = icon;
      });
    } catch (_) {
      // si falla, se mantiene el marcador por defecto
    }
  }

  Future<void> _loadClientIcon() async {
    try {
      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() {
        _clientIcon = icon;
      });
    } catch (_) {
      // si falla, se mantiene el marcador por defecto
    }
  }


  Future<void> _sendChatMessage() async {
    final texto = _chatController.text.trim();
    if (texto.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _chatService.sendMessage(
        solicitudId: widget.solicitudId,
        senderId: uid ?? '',
        texto: texto,
      );
      _chatController.clear();
      await Future.delayed(const Duration(milliseconds: 60));
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent + 24,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {}
  }

  Future<void> _openChatSheet() async {
    // Al abrir el chat, limpiar el indicador de "nuevo mensaje" en el VM
    _vm.clearNewChatFlag();
    setState(() {
      _isChatOpen = true;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets;
        final keyboardOpen = viewInsets.bottom > 0;
        final initialSize = keyboardOpen ? 0.9 : 0.55;
        final minSize = keyboardOpen ? 0.6 : 0.35;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_chatFocusNode.canRequestFocus) {
            _chatFocusNode.requestFocus();
          }
        });
        return Padding(
          padding: EdgeInsets.only(
            bottom: viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: initialSize,
            minChildSize: minSize,
            maxChildSize: 0.95,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(blurRadius: 16, color: Colors.black26),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Chat con tu conductor',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            FocusScope.of(ctx).unfocus();
                            Navigator.of(ctx).pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: StreamBuilder<List<ChatMessage>>(
                          stream: _chatService.listenMessages(widget.solicitudId),
                          initialData: const [],
                          builder: (context, snapshot) {
                            final mensajes = snapshot.data ?? const <ChatMessage>[];
                            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_chatScrollController.hasClients) {
                                _chatScrollController.jumpTo(
                                  _chatScrollController.position.maxScrollExtent,
                                );
                              }
                            });
                            if (mensajes.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Aún no hay mensajes.\nEscribe el primero.',
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }
                            return ListView.builder(
                              controller: _chatScrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: mensajes.length,
                              itemBuilder: (_, i) {
                                final m = mensajes[i];
                                final esMio = m.senderId == uid;
                                final ts = m.timestamp;
                                final hhmm = ts != null
                                    ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                                    : '';
                                return Align(
                                  alignment: esMio
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    decoration: BoxDecoration(
                                      color: esMio
                                          ? Colores.amarillo
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.black12,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          m.texto,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        if (hhmm.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              hhmm,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            focusNode: _chatFocusNode,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Escribe un mensaje...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(20)),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colores.amarillo),
                          onPressed: _sendChatMessage,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (mounted) {
      setState(() {
        _isChatOpen = false;
      });
      FocusScope.of(context).unfocus();
    }
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await Future.delayed(const Duration(milliseconds: 50));
    _fitBoundsToMarkers();
  }

  Future<void> _fitBoundsToMarkers() async {
    try {
      if (_mapController == null) return;
      // Intentar centrar ambos marcadores (cliente + conductor) si están disponibles
      LatLng? clientePos;
      LatLng? conductorPos;
      for (final m in _vm.markers) {
        if (m.markerId.value == 'cliente') clientePos = m.position;
        if (m.markerId.value == 'conductor') conductorPos = m.position;
      }

      if (clientePos != null && conductorPos != null) {
        final center = LatLng(
          (clientePos.latitude + conductorPos.latitude) / 2,
          (clientePos.longitude + conductorPos.longitude) / 2,
        );

        final distanceMeters = _haversineDistanceMeters(clientePos, conductorPos);
        final zoom = _zoomForDistanceMeters(distanceMeters);
        try {
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: center, zoom: zoom, bearing: 0.0, tilt: 0.0),
            ),
          );
          return;
        } catch (_) {
          // Fallback a LatLngBounds si falla
          try {
            final bounds = LatLngBounds(
              southwest: LatLng(
                math.min(clientePos.latitude, conductorPos.latitude),
                math.min(clientePos.longitude, conductorPos.longitude),
              ),
              northeast: LatLng(
                math.max(clientePos.latitude, conductorPos.latitude),
                math.max(clientePos.longitude, conductorPos.longitude),
              ),
            );
            await _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 120),
            );
            return;
          } catch (_) {}
        }
      }

      // Si no tenemos ambos marcadores, usar los bounds provistos por el ViewModel
      final bounds = _vm.cameraBounds;
      if (bounds == null) return;
      // Calcular distancia aproximada usando la diagonal del bounds
      final sw = bounds.southwest;
      final ne = bounds.northeast;
      final diagonalMeters = _haversineDistanceMeters(sw, ne);
      // Centrar y ajustar zoom de manera que ambos marcadores queden visibles
      final center = LatLng(
        (sw.latitude + ne.latitude) / 2,
        (sw.longitude + ne.longitude) / 2,
      );

      

      // Ajuste leve para compensar que la diagonal es mayor que la distancia real
      final zoom = _zoomForDistanceMeters(diagonalMeters / 1.5);
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: center, zoom: zoom, bearing: 0.0, tilt: 0.0),
          ),
        );
      } catch (_) {
        // Fallback a bounds si falla la animación con CameraPosition
        try {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 160),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180);
    final lat2 = to.latitude * (math.pi / 180);
    final dLon = (to.longitude - from.longitude) * (math.pi / 180);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (brng * 180 / math.pi + 360) % 360;
  }

  Future<void> _showCancelConfirmDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(
                  '¿Desea cancelar el servicio?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Cancelar',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        color: Colors.grey.shade300,
                        textColor: Colors.black87,
                        fontSize: ResponsiveHelper.sp(context, 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomButton(
                        text: 'Aceptar',
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _cancelSolicitudFromRoute();
                        },
                        color: Colores.amarillo,
                        textColor: Colores.blanco,
                        fontSize: ResponsiveHelper.sp(context, 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Future<void> _cancelSolicitudFromRoute() async {
    final ok = await _vm.cancelSolicitudFromRoute();
    if (!mounted) return;
    if (ok) {
      try {
        await RouteCacheService.clearSolicitud(widget.solicitudId);
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Solicitud cancelada' : 'Error al cancelar'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RutaClienteViewModel>.value(
      value: _vm,
      child: Consumer<RutaClienteViewModel>(
        builder: (context, vm, _) {
          // Cache persistence is handled in `RutaClienteViewModel` now.
          if (vm.cancelStatusHandled && !_handledCancelNavigation) {
            _handledCancelNavigation = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const LoaderVolviendoAtrasView(),
                ),
              );
            });
          }

          if (vm.goToDestino && !_handledDestinoNavigation) {
            _handledDestinoNavigation = true;
            vm.consumeGoToDestino();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RutaDestinoClienteView(
                    solicitudId: widget.solicitudId,
                  ),
                ),
              );
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _fitBoundsToMarkers();
            }
          });

          

            final conductorPhotoUrl = vm.conductorPhotoUrl ?? _routeCache?.conductorPhotoUrl;
            final conductorVehiclePhotoUrl = vm.conductorVehiclePhotoUrl ?? _routeCache?.conductorVehiclePhotoUrl;
            final conductorPlate = vm.conductorPlate ?? _routeCache?.conductorPlate;
            final conductorName = vm.conductorDisplayName ?? _routeCache?.conductorName;
            final conductorRatingFallback = vm.conductorRating ?? _routeCache?.conductorRating;
            final conductorDocId = vm.conductorId ?? _routeCache?.conductorId;

            final hasConductorInfo =
              conductorPlate != null ||
              conductorPhotoUrl != null ||
              conductorRatingFallback != null ||
              conductorName != null;

          final markers = vm.markers.map((m) {
            if (m.markerId.value == 'cliente' && _clientIcon != null) {
              return m.copyWith(iconParam: _clientIcon);
            }
            if (m.markerId.value == 'conductor' && _taxiIcon != null) {
              return m.copyWith(
                iconParam: _taxiIcon,
                rotationParam: _vm.conductorBearing ?? 0.0,
                anchorParam: const Offset(0.5, 0.5),
                flatParam: true,
              );
            }
            return m;
          }).toSet();

          return WillPopScope(
            onWillPop: () async => false,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: SafeArea(
              top: true,
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Builder(
                        builder: (context) {
                          final width =
                              MediaQuery.of(context).size.width;
                          return Stack(
                            children: [
                              Container(
                                width: width,
                                margin: EdgeInsets.zero,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: vm.loading
                                    ? const Center(
                                        child:
                                            CircularProgressIndicator(),
                                      )
                                    : (markers.isEmpty
                                        ? Center(
                                            child: Icon(
                                              Icons.map,
                                              size: ResponsiveHelper.sp(context, 36),
                                              color: Colors.grey.shade300,
                                            ),
                                          )
                                        : AppGoogleMap(
                                            initialTarget:
                                                vm.initialTarget,
                                            initialZoom: vm.zoom,
                                            onMapCreated:
                                                _onMapCreated,
                                            markers: markers,
                                            polylines: vm.polylines,
                                            myLocationEnabled: false,
                                            myLocationButtonEnabled:
                                                false,
                                            compassEnabled: true,
                                          )),
                              ),
                              if (vm.routeDurationMin != null)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                        top: 25),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(0.15),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                              Icons.access_time,
                                              size: ResponsiveHelper.sp(context, 16),
                                              color: Colors.black87,
                                            ),
                                            SizedBox(width: ResponsiveHelper.wp(context, 2)),
                                            Text(
                                              'Tiempo estimado de llegada: ${vm.routeDurationMin!.round()} min',
                                              style: TextStyle(
                                                fontSize: ResponsiveHelper.sp(context, 16),
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                            ),
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
                  SafeArea(
                    top: false,
                    bottom: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.only(
                        left: ResponsiveHelper.wp(context, 6),
                        right: ResponsiveHelper.wp(context, 6),
                        top: 20,
                        bottom: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasConductorInfo) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: ResponsiveHelper.sp(context, 34),
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: conductorPhotoUrl != null
                                          ? NetworkImage(conductorPhotoUrl)
                                          : null,
                                      child: conductorPhotoUrl == null
                                          ? Icon(
                                              Icons.person,
                                              size: ResponsiveHelper.sp(context, 22),
                                              color: Colors.black87,
                                            )
                                          : null,
                                    ),
                                    SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                                    if (conductorName != null)
                                      Text(
                                        conductorName.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: ResponsiveHelper.sp(context, 14),
                                          fontWeight: FontWeight.w700,
                                          color: Colores.negro,
                                        ),
                                      ),
                                    SizedBox(height: ResponsiveHelper.hp(context, 0.3)),
                                    StreamBuilder<DocumentSnapshot>(
                                      stream: vm.conductorId != null
                                          ? FirebaseFirestore.instance
                                              .collection('conductor')
                                              .doc(vm.conductorId)
                                              .snapshots()
                                          : null,
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData && snapshot.data!.exists) {
                                          final data = snapshot.data!.data() as Map<String, dynamic>?;
                                          final promedio = (data?['calificacion_promedio'] as num?)?.toDouble() ?? 0.0;
                                          final promedioInt = promedio.toInt();
                                          final tieneMedia = (promedio - promedioInt) >= 0.5;
                                          return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(5, (index) {
                                                  if (index < promedioInt) {
                                                    return Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                      child: Icon(
                                                        Icons.star,
                                                        size: ResponsiveHelper.sp(context, 12),
                                                        color: Colors.amber,
                                                      ),
                                                    );
                                                  } else if (index == promedioInt && tieneMedia) {
                                                    return Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                      child: Icon(
                                                        Icons.star_half,
                                                        size: ResponsiveHelper.sp(context, 12),
                                                        color: Colors.amber,
                                                      ),
                                                    );
                                                  } else {
                                                    return Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                      child: Icon(
                                                        Icons.star_border,
                                                        size: ResponsiveHelper.sp(context, 12),
                                                        color: Colors.grey[400],
                                                      ),
                                                    );
                                                  }
                                                }),
                                              );
                                        }

                                        // Fallback a cache si no hay stream/datos
                                        final promedio = conductorRatingFallback ?? 0.0;
                                        if (promedio <= 0) {
                                          return const SizedBox.shrink();
                                        }
                                        final promedioInt = promedio.toInt();
                                        final tieneMedia = (promedio - promedioInt) >= 0.5;
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: List.generate(5, (index) {
                                            if (index < promedioInt) {
                                              return const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 1.0),
                                                child: Icon(
                                                  Icons.star,
                                                  size: 14,
                                                  color: Colors.amber,
                                                ),
                                              );
                                            } else if (index == promedioInt && tieneMedia) {
                                              return const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 1.0),
                                                child: Icon(
                                                  Icons.star_half,
                                                  size: 14,
                                                  color: Colors.amber,
                                                ),
                                              );
                                            } else {
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 1.0),
                                                child: Icon(
                                                  Icons.star_border,
                                                  size: 14,
                                                  color: Colors.grey, 
                                                ),
                                              );
                                            }
                                          }),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                if (conductorPlate != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (conductorVehiclePhotoUrl != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            conductorVehiclePhotoUrl,
                                            height: ResponsiveHelper.hp(context, 8),
                                            width: ResponsiveHelper.wp(context, 30),
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => Image.asset(
                                              'assets/img/carrito.png',
                                              height: ResponsiveHelper.hp(context, 10),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        )
                                      else
                                        Image.asset(
                                          'assets/img/carrito.png',
                                          height: ResponsiveHelper.hp(context, 8),
                                          fit: BoxFit.contain,
                                        ),
                                      Text(
                                        conductorPlate,
                                        style: TextStyle(
                                          fontSize: ResponsiveHelper.sp(context, 14),
                                          fontWeight: FontWeight.w700,
                                          color: Colores.negro,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 2)),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _openChatSheet,
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(Icons.chat_bubble_outline, size: ResponsiveHelper.sp(context, 16)),
                                        if (vm.hasNewChat && !_isChatOpen)
                                          Positioned(
                                            right: -ResponsiveHelper.wp(context, 1),
                                            top: -ResponsiveHelper.hp(context, 0.6),
                                            child: Container(
                                              width: ResponsiveHelper.sp(context, 6),
                                              height: ResponsiveHelper.sp(context, 6),
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    label: Text('Chat', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppColores.primary,
                                      side: BorderSide(color: AppColores.primary),
                                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.wp(context, 3)),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _showCancelConfirmDialog,
                                    icon: Icon(Icons.cancel, size: ResponsiveHelper.sp(context, 16)),
                                    label: Text('Cancelar', style: TextStyle(fontSize: ResponsiveHelper.sp(context, 14))),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colores.amarillo,
                                      foregroundColor: Colores.blanco,
                                      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 1.2)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

/// Pantalla intermedia que muestra un loader mientras se regresa
/// automáticamente a la vista de inicio del cliente.
class LoaderVolviendoAtrasView extends StatefulWidget {
  const LoaderVolviendoAtrasView({super.key});

  @override
  State<LoaderVolviendoAtrasView> createState() => _LoaderVolviendoAtrasViewState();
}

class _LoaderVolviendoAtrasViewState extends State<LoaderVolviendoAtrasView> {
  @override
  void initState() {
    super.initState();
    _goBackAfterDelay();
  }

  void _goBackAfterDelay() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioClienteView()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: MapLoadingWidget(
            message: 'Volviendo atrás...'
          ),
        ),
      ),
    );
  }
}

// Using shared CustomYellowButton from widgets/custom_yellow_button.dart
