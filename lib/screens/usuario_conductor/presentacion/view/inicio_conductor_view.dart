import 'dart:math' as math;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/historial_viaje_conductor.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/inicio_conductor_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/services/notification_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/widgets/perfil.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/widgets/preview_solicitud_card.dart';
import 'package:taxi_app/widgets/solicitud_card.dart';
import 'ruta_conductor_view.dart';


class HomeConductorMapView extends StatefulWidget {
  const HomeConductorMapView({Key? key}) : super(key: key);

  @override
  State<HomeConductorMapView> createState() => _HomeConductorMapViewState();
}

class _HomeConductorMapViewState extends State<HomeConductorMapView> {
  GoogleMapController? _mapController;
  bool _hasCentered = false;
  StreamSubscription<DocumentSnapshot>? _previewSub;
  StreamSubscription<String?>? _cachedNameSub;
  bool _navigatingToRuta = false;
  StreamSubscription<String>? _newSolicitudSub;
  bool _isTogglingConnection = false;

  // Expande el mapa ocultando la barra; luego centra los marcadores tras 2s
  Future<void> _expandMapAndCenter(PreviewSolicitud preview, HomeConductorViewModel vm) async {
    if (!mounted) return;
    vm.setMapExpanded(true);

    // Wait 2 seconds to allow UI animation / bottom bar hiding
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      final s = preview.solicitud;
      final client = LatLng(s.ubicacionInicial.latitude, s.ubicacionInicial.longitude);
      if (vm.currentLocation != null) {
        await _animateToInclude(vm.currentLocation!, client);
        // Try to fetch route for better polyline (non-blocking)
        _fetchRouteOSRM(s.id, vm.currentLocation!, client, vm);
      } else {
        await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(client, 16));
      }
    } catch (_) {}
  }

  // Centraliza el cierre/retroceso de la preview para poder invocarlo
  // desde el listener cuando la solicitud cambie a cancelada.
  Future<void> _closePreview(HomeConductorViewModel vm) async {
    if (_previewSub != null) {
      try {
        await _previewSub!.cancel();
      } catch (e) {
        // Some platform plugins may throw "No active stream to cancel" when
        // canceling an already-cancelled native stream; ignore that specific error.
      }
    }
    if (!mounted) return;
    vm.clearPreviewAndRoutes();
    if (vm.currentLocation != null) {
      try {
        await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(vm.currentLocation!, 16));
      } catch (_) {}
    }
  }

  Future<void> _toggleConductorConnection() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isTogglingConnection = true);
    try {
      final docRef = FirebaseFirestore.instance.collection('conductor').doc(uid);
      final snap = await docRef.get();
      final current = snap.exists && (snap.data()?['conectado'] == true);
      final newVal = !current;
      await docRef.update({'conectado': newVal});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error actualizando estado: $e')));
    } finally {
      if (mounted) setState(() => _isTogglingConnection = false);
    }
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);
  double _rad2deg(double rad) => rad * (180.0 / math.pi);

  double _calculateBearing(LatLng a, LatLng b) {
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    var brng = math.atan2(y, x);
    brng = _rad2deg(brng);
    return (brng + 360) % 360;
  }

  Future<void> _fetchRouteOSRM(String id, LatLng origin, LatLng dest, HomeConductorViewModel vm) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson');
      final resp = await http.get(url).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = json.decode(resp.body) as Map<String, dynamic>?;
      if (data == null) return;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;
      final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
      if (geometry == null || geometry['coordinates'] == null) return;
      final coords = geometry['coordinates'] as List;
      final points = coords.map<LatLng>((c) {
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        return LatLng(lat, lon);
      }).toList();

      if (!mounted) return;
      vm.setRoute(id, points);
    } catch (_) {}
  }

  Future<void> _animateToInclude(LatLng a, LatLng b) async {
    if (_mapController == null) return;
    try {
      final south = LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude));
      final north = LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude));
      final bounds = LatLngBounds(southwest: south, northeast: north);
      await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    } catch (_) {
      try {
        await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(b, 16));
      } catch (_) {}
    }
  }

  // Preview card height: make responsive (45% of screen height)
  double get _previewHeight => MediaQuery.of(context).size.height * 0.35;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HomeConductorViewModel>(
      create: (context) {
        final vm = HomeConductorViewModel();
        // Request necessary permissions for drivers (notifications, foreground and background location)
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await PermissionsHelper.requestAllPermissions(isDriver: true);
          } catch (_) {}
          // Initialize local notifications
          try {
            await NotificationService.instance.init();
          } catch (_) {}
          await vm.init();
        });
        return vm;
      },
      child: Consumer<HomeConductorViewModel>(builder: (context, vm, _) {
        // Si ya tenemos controlador y ubicación, centrar el mapa una sola vez.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hasCentered && _mapController != null && vm.currentLocation != null) {
            _hasCentered = true;
            vm.centerMapOnMarker(_mapController!, zoom: vm.currentLocation != null ? 16.0 : 14.5);
          }
        });

        // Suscribirse una sola vez a cambios del nombre guardado en cache
        if (_cachedNameSub == null) {
          _cachedNameSub = SessionHelper.cachedNameStream.listen((name) {
            if (!mounted) return;
            if (name != null && name.trim().isNotEmpty) {
              vm.displayName = name.trim();
              try {
                vm.notifyListeners();
              } catch (_) {}
            }
          });

          // Aplicar valor cached actual si existe
          SessionHelper.getCachedName().then((n) {
            if (!mounted) return;
            if (n != null && n.trim().isNotEmpty) {
              vm.displayName = n.trim();
              try { vm.notifyListeners(); } catch (_) {}
            }
          }).catchError((_) {});
        }



        final bool _hasPreview = vm.selectedPreview != null;

        // Prepare conductor document stream once here (avoid declaring statements inside widget trees)
        final _currentUid = FirebaseAuth.instance.currentUser?.uid;
        Stream<DocumentSnapshot<Object?>>? _conductorStream;
        if (_currentUid != null && _currentUid.isNotEmpty) {
          _conductorStream = FirebaseFirestore.instance.collection('conductor').doc(_currentUid).snapshots();
        } else {
          _conductorStream = null;
        }
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: _hasPreview
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                ),
          body: SafeArea(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    // Nombre y placa arriba (dentro de un marco) -- ocultar cuando hay preview seleccionada
                    if (vm.selectedPreview == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 5.0, 16.0, 8.0),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 110),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(color: Colors.black12, width: 1.2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      vm.displayName.toUpperCase(),
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                                    ),

                                    const SizedBox(height: 10.0),
                                    // Estrellas de calificación calculadas a partir de la colección `solicitudes`
                                    Builder(builder: (ctx) {
                                      final uidForRating = FirebaseAuth.instance.currentUser?.uid;
                                      if (uidForRating == null || uidForRating.isEmpty) {
                                        return Row(
                                          children: const [
                                            Icon(Icons.star_border, color: Colors.grey, size: 18),
                                            SizedBox(width: 8),
                                            Text('0.0', style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w700)),
                                          ],
                                        );
                                      }

                                      final solicitudesStream = FirebaseFirestore.instance
                                          .collection('solicitudes')
                                          .where('conductor.id', isEqualTo: uidForRating)
                                          .snapshots();

                                      return StreamBuilder<QuerySnapshot>(
                                        stream: solicitudesStream,
                                        builder: (context, snap) {
                                          double promedio = 0.0;
                                          int totalCalificaciones = 0;
                                          if (snap.hasData && snap.data != null) {
                                            for (var doc in snap.data!.docs) {
                                              try {
                                                final data = doc.data() as Map<String, dynamic>?;
                                                final calificacionObj = data == null ? null : (data['calificacion'] ?? data['calificacion_cliente']);
                                                if (calificacionObj is Map && calificacionObj['score'] != null) {
                                                  promedio += (calificacionObj['score'] as num).toDouble();
                                                  totalCalificaciones++;
                                                }
                                              } catch (_) {}
                                            }
                                            if (totalCalificaciones > 0) promedio = promedio / totalCalificaciones;
                                          }

                                          final promedioInt = promedio.toInt();
                                          final tieneMedia = (promedio - promedioInt) >= 0.5;

                                          return Row(
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(5, (index) {
                                                  if (index < promedioInt) {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(right: 4),
                                                      child: Icon(Icons.star, color: Colors.amber, size: 18),
                                                    );
                                                  } else if (index == promedioInt && tieneMedia) {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(right: 4),
                                                      child: Icon(Icons.star_half, color: Colors.amber, size: 18),
                                                    );
                                                  } else {
                                                    return Padding(
                                                      padding: const EdgeInsets.only(right: 4),
                                                      child: Icon(Icons.star_border, color: Colors.grey[400], size: 18),
                                                    );
                                                  }
                                                }),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                promedio > 0 ? promedio.toStringAsFixed(1) : '0.0',
                                                style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w700),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12.0),
                              // Foto circular del conductor: escuchar el documento `conductor`
                              StreamBuilder<DocumentSnapshot?>(
                                stream: _conductorStream,
                                builder: (ctx, snap) {
                                  String photoUrl = vm.photoUrl ?? '';
                                  if (snap.hasData && snap.data != null && snap.data!.exists) {
                                    try {
                                      final data = snap.data!.data() as Map<String, dynamic>?;
                                      final p = data == null ? null : (data['foto'] as String?);
                                      if (p != null && p.isNotEmpty) photoUrl = p;
                                    } catch (_) {}
                                  }

                                  if (photoUrl.isNotEmpty) {
                                    return ClipOval(
                                      child: Image.network(
                                        photoUrl,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx2, error, stack) {
                                          return Container(
                                            width: 100,
                                            height: 100,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              vm.displayName.isNotEmpty ? vm.displayName.trim()[0].toUpperCase() : 'C',
                                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black87),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  }

                                  return Container(
                                    width: 100,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      vm.displayName.isNotEmpty ? vm.displayName.trim()[0].toUpperCase() : 'C',
                                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.black87),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Reserva espacio para la preview cuando está seleccionada
                    // pero solo si NO hemos expandido el mapa (tap reciente).
                    if (vm.selectedPreview != null && !vm.isMapExpanded) SizedBox(height: _previewHeight + 0),

                    // Mapa colocado justo bajo el contenedor de información y ocupa el espacio restante
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                        child: Container(
                              height: double.infinity,
                              width: double.infinity,
                                decoration: vm.selectedPreview == null
                                  ? BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black, width: 1.2),
                                    )
                                  : const BoxDecoration(
                                      color: Colors.transparent,
                                    ),
                              child: Stack(
                            children: [
                                  ClipRRect(
                                    borderRadius: vm.selectedPreview == null ? BorderRadius.circular(12) : BorderRadius.zero,
                                    child: Builder(builder: (context) {
                                  final markers = <Marker>{};
                                  final polylines = <Polyline>{};
                                  // We use the map's default my-location blue dot (`myLocationEnabled`) instead
                                  // of adding a custom driver marker to avoid duplicate/red markers.
                                  final preview = vm.selectedPreview;
                                  if (preview != null) {
                                    final s = preview.solicitud;
                                    final clientPos = LatLng(s.ubicacionInicial.latitude, s.ubicacionInicial.longitude);
                                    markers.add(Marker(
                                      markerId: MarkerId('client_${s.id}'),
                                      position: clientPos,
                                      infoWindow: InfoWindow(title: s.nombreCliente ?? 'Cliente', snippet: s.direccion),
                                    ));
                                    if (vm.currentLocation != null) {
                                      final hasRouted = vm.routePolylines.any((p) => p.polylineId.value == 'route_${s.id}');
                                      if (!hasRouted) {
                                        polylines.add(Polyline(
                                          polylineId: PolylineId('route_${s.id}'),
                                          points: [vm.currentLocation!, clientPos],
                                          color: AppColores.primary,
                                          width: 4,
                                        ));
                                      }
                                    }
                                  }

                                  return AppGoogleMap(
                                    initialTarget: vm.currentLocation ?? const LatLng(8.2595534, -73.353469),
                                    initialZoom: vm.currentLocation != null ? 16.0 : 14.5,
                                    myLocationEnabled: true,
                                    myLocationButtonEnabled: true,
                                    compassEnabled: true,
                                    markers: markers.union(vm.extraMarkers),
                                    polylines: polylines.union(vm.routePolylines),
                                    onMapCreated: (controller) async {
                                      _mapController = controller;
                                      if (vm.currentLocation != null) {
                                        try {
                                          await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(vm.currentLocation!, 16));
                                          _hasCentered = true;
                                        } catch (_) {}
                                      }
                                    },
                                  );
                                }),
                              ),

                              // Lista de solicitudes flotante encima del mapa (apiladas verticalmente)
                              Positioned(
                                top: 12,
                                left: 12,
                                right: 12,
                                child: Builder(builder: (context) {
                                  final sols = vm.solicitudes;
                                  if (sols.isEmpty) return const SizedBox.shrink();

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Encabezado único
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade600,
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: const [
                                              BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                                            ],
                                          ),
                                          child: const Text('Solicitud pendiente', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(height: 8),

                                        // Contenedor desplazable con máximo alto para no tapar todo el mapa
                                        if (vm.selectedPreview == null)
                                          ConstrainedBox(
                                            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
                                            child: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(sols.length, (i) {
                                                  final s = sols[i];
                                                  return Padding(
                                                    padding: EdgeInsets.only(bottom: i == sols.length - 1 ? 0 : 8),
                                                    child: SizedBox(
                                                      width: MediaQuery.of(context).size.width * 0.92,
                                                      child: SolicitudCard(
                                                        solicitud: s,
                                                        expanded: false,
                                                        onTap: (preview) async {
                                                            final s = preview.solicitud;
                                                            vm.selectPreview(preview);

                                                            // Cancel any previous preview listener and subscribe to this solicitud document
                                                            if (_previewSub != null) {
                                                              try {
                                                                await _previewSub!.cancel();
                                                              } catch (e) {
                                                                // ignore platform "No active stream to cancel"
                                                              }
                                                            }
                                                            _previewSub = FirebaseFirestore.instance.collection('solicitudes').doc(s.id).snapshots().listen((snap) async {
                                                              if (!mounted) return;
                                                              try {
                                                                if (!snap.exists) {
                                                                  // treated as cancelled/removed
                                                                      await _closePreview(vm);
                                                                  return;
                                                                }

                                                                final Map<String, dynamic>? data = snap.data() as Map<String, dynamic>?;
                                                                final dynamic st = (data != null) ? (data['estado'] ?? data['status']) : null;
                                                                if (st is String) {
                                                                  final sLower = st.toLowerCase();
                                                                  // Cancelado: cerrar preview
                                                                  if (sLower.contains('cancel') || sLower.contains('anulad')) {
                                                                    await _closePreview(vm);
                                                                    return;
                                                                  }

                                                                  // Asignado: cerrar preview y navegar a la ruta (con loader). Evitar navegaciones duplicadas.
                                                                  if (sLower.contains('asign')) {
                                                                    if (_navigatingToRuta) return;
                                                                    _navigatingToRuta = true;
                                                                    await _closePreview(vm);

                                                                    if (!mounted) return;
                                                                    final navCtx = this.context;
                                                                    try {
                                                                      // Show a loading screen for 5 seconds so the route view can prepare
                                                                      await Navigator.of(navCtx).push(
                                                                        MaterialPageRoute(
                                                                          builder: (_) => RutaConductorLoadingView(
                                                                            solicitudId: s.id,
                                                                            clientLocation: LatLng(
                                                                              s.ubicacionInicial.latitude,
                                                                              s.ubicacionInicial.longitude,
                                                                            ),
                                                                            clientName: s.nombreCliente,
                                                                            clientAddress: s.direccion,
                                                                            driverLocation: vm.currentLocation,
                                                                          ),
                                                                        ),
                                                                      );
                                                                    } catch (_) {}

                                                                    _navigatingToRuta = false;
                                                                    return;
                                                                  }
                                                                }
                                                              } catch (_) {}
                                                            });

                                                            if (vm.currentLocation != null) {
                                                              final driver = vm.currentLocation!;
                                                              final client = LatLng(s.ubicacionInicial.latitude, s.ubicacionInicial.longitude);
                                                              await _animateToInclude(driver, client);
                                                              // Try to fetch a routed polyline (OSRM) for better trazability
                                                              _fetchRouteOSRM(s.id, driver, client, vm);
                                                            } else {
                                                              await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(s.ubicacionInicial.latitude, s.ubicacionInicial.longitude), 16));
                                                            }
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                }),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Botón de conexión colocado debajo del mapa, ancho completo
                    if (!vm.isMapExpanded && vm.selectedPreview == null && _conductorStream != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        child: StreamBuilder<DocumentSnapshot?>(
                          stream: _conductorStream,
                          builder: (ctx, snap) {
                            final connected = snap.hasData && snap.data != null && (snap.data!.data() as Map<String, dynamic>?)?['conectado'] == true;
                            return SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: _isTogglingConnection ? null : _toggleConductorConnection,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: connected ? AppColores.buttonPrimary : Colors.grey,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: _isTogglingConnection
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Icon(connected ? Icons.toggle_on : Icons.toggle_off, size: 28),
                                label: Text(connected ? 'Conectado' : 'Desconectado', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                // Selected solicitud preview: in-flow so the map appears below it
                if (vm.selectedPreview != null)
                  Builder(builder: (context) {
                    final preview = vm.selectedPreview!;
                    final s = preview.solicitud;
                    final statusBar = MediaQuery.of(context).padding.top;
                      final top = statusBar + (kToolbarHeight / 200); // overlap AppBar center, but stay below status bar
                    return Positioned(
                      top: top,
                      left: 5,
                      right: 5,
                      height: _previewHeight,
                        child: GestureDetector(
                          onTap: () => _expandMapAndCenter(preview, vm),
                          child: PreviewSolicitudCard(
                            preview: preview,
                            isLoading: false,
                            onClose: () async {
                              await _closePreview(vm);
                            },
                            onCancel: () async {
                              await _closePreview(vm);
                            },
                            onAccept: () async {
                              try {
                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                if (uid == null) return;
                                
                                await FirebaseFirestore.instance
                                    .collection('solicitudes')
                                    .doc(s.id)
                                    .update({
                                  'status': 'asignado',
                                  'conductor': {
                                    if (uid != null) 'id': uid,
                                    'nombre': vm.displayName,
                                    if (vm.photoUrl != null) 'foto': vm.photoUrl,
                                    'placa': vm.vehiclePlate ?? '',
                                    if (vm.currentLocation != null)
                                      'lat': vm.currentLocation!.latitude,
                                    if (vm.currentLocation != null)
                                      'lng': vm.currentLocation!.longitude,
                                  },
                                  'fecha de aceptacion conductor': FieldValue.serverTimestamp(),
                                });
                              } catch (_) {}
                          },
                        ),
                        ),
                    );
                  }),
              ],
            ),
          ),
          // floatingActionButton removed — button is placed below the map in the Column
            bottomNavigationBar: !vm.isMapExpanded && vm.selectedPreview == null
              ? BottomNavigationBar(
                  currentIndex: 0,
                  selectedItemColor: Colors.amber,
                  unselectedItemColor: Colors.black54,
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
                    BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Historial'),
                    BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Tú'),
                  ],
                  onTap: (index) async {
                    if (index == 0) {
                      // Ir a la pantalla principal del conductor (reemplaza la ruta actual)
                      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeConductorMapView()));
                      return;
                    }
                    if (index == 1) {
                      // Navegar al historial del conductor
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistorialConductor()));
                      return;
                    }
                    if (index == 2) {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaginaPerfilUsuario(tipoUsuario: 'conductor')));
                    }
                  },
                )
              : null,
        );
      }),
    );
  }

  @override
  void dispose() {
    final f = _previewSub?.cancel();
    f?.catchError((e) {
      // ignore platform "No active stream to cancel"
    });
    try { _newSolicitudSub?.cancel(); } catch (_) {}
    try {
      final f2 = _cachedNameSub?.cancel();
      f2?.catchError((e) {});
    } catch (_) {}
    _mapController = null;
    super.dispose();
  }
}
