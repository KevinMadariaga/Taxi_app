import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;
  final double defaultMarkerHue;
  const BuscandoTaxiView({Key? key, this.solicitudId, this.defaultMarkerHue = BitmapDescriptor.hueYellow}) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView>
    with TickerProviderStateMixin {
  late final BuscandoTaxiViewModel _vm;
  late final AnimationController _taxiController;
  late final AnimationController _dotsController;

  GoogleMapController? _mapController;
  BitmapDescriptor? _taxiIcon;
  BitmapDescriptor? _smallTaxiIcon;
  BitmapDescriptor? _bigTaxiIcon;
  double _sonarRadius = 220.0;
  Timer? _sonarTimer;
  Timer? _searchTimer;
  int _searchSeconds = 0;
  final LatLng _defaultCenter = const LatLng(
    8.2595534,
    -73.353469,
  ); // centro (ejemplo)
  LatLng? _clientLocation;
  Set<Marker> _taxiMarkers = {};
  Set<Marker> _conectadosMarkers = {};
  final Map<String, LatLng> _allConectadosPositions = {};
  final Set<String> _visibleConectadosIds = {};
  Set<Circle> _sonarCircles = {};
  Set<Circle> _clientCircles = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _conductoresSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _conductoresConectadosSub;

  @override
  void initState() {
    super.initState();
    _initializeSonarMap();

    _startSearchTimer();

    _taxiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _vm = BuscandoTaxiViewModel();
    _vm.addListener(_onVmChanged);
    _vm.iniciarEscucha(
      solicitudId: widget.solicitudId,
      onAsignada: _onSolicitudAsignada,
    );
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onSolicitudAsignada(String solicitudId) async {
    if (!mounted) return;

    await _vm.detenerEscucha();
    if (!mounted) return;

    _searchTimer?.cancel();
    _sonarTimer?.cancel();
    _conductoresConectadosSub?.cancel();

    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => TripTrackingScreen(
        solicitudId: solicitudId,
        currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
        cancelledBy: 'cliente',
        onSolicitudCancelada: () {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeClienteView()),
            (route) => false,
          );
        },
      ),
      title: 'Conductor encontrado',
      subtitle: 'Preparando tu ruta y detalles del viaje...',
    );
  }

  void _initializeSonarMap() {
    _loadTaxiIcon();
    _loadSmallTaxiIcon();
    _initClientLocation();
    _subscribeConductores();
    _subscribeConductoresConectados();

    _sonarCircles = {
      Circle(
        circleId: const CircleId('sonar'),
        center: _clientLocation ?? _defaultCenter,
        radius: _sonarRadius,
        strokeColor: AppColores.primary.withOpacity(0.4),
        strokeWidth: 2,
        fillColor: AppColores.primary.withOpacity(0.12),
      ),
    };

    _sonarTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted) return;
      setState(() {
        _sonarRadius += 50;
        if (_sonarRadius > 700) {
          _sonarRadius = 250;
        }
        _sonarCircles = {
          Circle(
            circleId: const CircleId('sonar'),
            center: _clientLocation ?? _defaultCenter,
            radius: _sonarRadius,
            strokeColor: AppColores.primary,
            strokeWidth: 2,
            fillColor: AppColores.primary.withOpacity(0.08),
          ),
        };
          _updateVisibleConectadosMarkers();
      });
    });
  }

  Future<void> _loadTaxiIcon() async {
    try {
      _taxiIcon = await _bitmapDescriptorFromAsset('assets/img/taxi_icon.png', 40);
      setState(() {
        _taxiMarkers = _taxiMarkers
            .map(
              (marker) => marker.copyWith(iconParam: _taxiIcon ?? marker.icon),
            )
            .toSet();
      });
    } catch (_) {
      // fallback si no existe el asset o hay error
    }
  }

  Future<void> _loadSmallTaxiIcon() async {
    try {
      // Create descriptors from bytes at explicit pixel widths so size changes take effect
      _smallTaxiIcon = await _bitmapDescriptorFromAsset('assets/img/taxi_icon.png', 42);
      try {
        _bigTaxiIcon = await _bitmapDescriptorFromAsset('assets/img/taxi_icon.png', 42);
      } catch (_) {}
      if (!mounted) return;
      _updateVisibleConectadosMarkers();
      setState(() {});
    } catch (_) {
      // ignore
    }
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromAsset(String path, int targetWidth) async {
    final byteData = await rootBundle.load(path);
    final bytes = byteData.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final pngBytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  void _startSearchTimer() {
    _searchTimer?.cancel();
    _searchSeconds = 0;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _searchSeconds++;
      });
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _initClientLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _clientLocation = LatLng(position.latitude, position.longitude);
      });
      _updateVisibleConectadosMarkers();
      _updateClientCircle();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_clientLocation!, 14),
      );
    } catch (_) {
      // No se pudo obtener, se queda en default
    }
  }

  void _updateClientCircle() {
    if (_clientLocation == null) {
      _clientCircles = {};
      return;
    }

    _clientCircles = {
      Circle(
        circleId: const CircleId('client_point'),
        center: _clientLocation!,
        radius: 30, // small dot (meters)
        strokeColor: AppColores.primary,
        strokeWidth: 2,
        fillColor: AppColores.primary,
      ),
    };
  }

  void _subscribeConductores() {
    _conductoresSub?.cancel();
    _conductoresSub = FirebaseFirestore.instance
        .collection('usuarios')
        .where('tipoUsuario', isEqualTo: 'conductor')
        .where('disponible', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            final markers = snapshot.docs
                .map((doc) {
                  final data = doc.data();
                  final ubicacion = data['ubicacion'];
                  if (ubicacion is! Map) return null;
                  final lat = ubicacion['lat'] ?? ubicacion['latitude'];
                  final lng = ubicacion['lng'] ?? ubicacion['longitude'];
                  if (lat == null || lng == null) return null;
                  return Marker(
                    markerId: MarkerId('taxi_${doc.id}'),
                    position: LatLng(
                      (lat as num).toDouble(),
                      (lng as num).toDouble(),
                    ),
                    icon:
                        _taxiIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueYellow,
                        ),
                    infoWindow: InfoWindow(
                      title: 'Taxi cercano',
                      snippet:
                          data['nombre']?.toString() ?? 'Conductor conectado',
                    ),
                  );
                })
                .whereType<Marker>()
                .toSet();

            if (!mounted) return;
            setState(() {
              _taxiMarkers = markers;
            });
          },
          onError: (_) {
            // ignore
          },
        );
  }

    void _subscribeConductoresConectados() {
      _conductoresConectadosSub?.cancel();
      _conductoresConectadosSub = FirebaseFirestore.instance
          .collection('conductores_conectados')
          .snapshots()
          .listen((snapshot) {
        // Store all connected drivers positions and then filter by sonar radius
        final positions = <String, LatLng>{};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final ubicacion = data['ubicacion'];
          if (ubicacion is! Map) continue;
          final lat = ubicacion['lat'] ?? ubicacion['latitude'];
          final lng = ubicacion['lng'] ?? ubicacion['longitude'];
          if (lat == null || lng == null) continue;
          positions[doc.id] = LatLng((lat as num).toDouble(), (lng as num).toDouble());
        }

        if (!mounted) return;
        _allConectadosPositions
          ..clear()
          ..addAll(positions);
        _updateVisibleConectadosMarkers();
        setState(() {});
      }, onError: (_) {
        // ignore
      });
    }

  void _updateVisibleConectadosMarkers() {
    final center = _clientLocation ?? _defaultCenter;
    final visible = <Marker>{};
    final newVisibleIds = <String>{};
    for (final entry in _allConectadosPositions.entries) {
      final id = entry.key;
      final pos = entry.value;
      final distance = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (distance <= _sonarRadius) {
        newVisibleIds.add(id);
        // If this marker just entered the visible set, show a brief "pop" with bigger icon
        if (!_visibleConectadosIds.contains(id)) {
          visible.add(Marker(
            markerId: MarkerId('conectado_$id'),
            position: pos,
            icon: _bigTaxiIcon ?? _smallTaxiIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            infoWindow: const InfoWindow(title: 'Conductor conectado'),
          ));

          // schedule to shrink back to small icon after a short delay
          Timer(const Duration(milliseconds: 420), () {
            if (!mounted) return;
            _conectadosMarkers = {
              ..._conectadosMarkers.where((m) => m.markerId.value != 'conectado_$id'),
              Marker(
                markerId: MarkerId('conectado_$id'),
                position: pos,
                icon: _smallTaxiIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                infoWindow: const InfoWindow(title: 'Conductor conectado'),
              ),
            };
            setState(() {});
          });
        } else {
          // already visible before, render with small icon
          visible.add(Marker(
            markerId: MarkerId('conectado_$id'),
            position: pos,
            icon: _smallTaxiIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            infoWindow: const InfoWindow(title: 'Conductor conectado'),
          ));
        }
      }
    }

    _visibleConectadosIds
      ..clear()
      ..addAll(newVisibleIds);

    // Merge visible with any transient markers currently in _conectadosMarkers
    // so brief pop icons are respected until they are replaced by the timer.
    final transient = _conectadosMarkers.where((m) => newVisibleIds.contains(m.markerId.value.replaceFirst('conectado_', ''))).toSet();
    _conectadosMarkers = {...visible, ...transient};
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_clientLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_clientLocation!, 14),
      );
    }
  }

  // Cliente marker removed — using Google Maps default blue dot (myLocationEnabled)

  @override
  void dispose() {
    _conductoresSub?.cancel();
    _conductoresConectadosSub?.cancel();
    _sonarTimer?.cancel();
    _searchTimer?.cancel();
    _mapController?.dispose();
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    _taxiController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  Future<void> _cancelSolicitud() async {
    if (_vm.isCancelling) return;

    await _vm.cancelarSolicitud();
    if (!mounted) return;

    _searchTimer?.cancel();
    _sonarTimer?.cancel();
    _conductoresConectadosSub?.cancel();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final bottomInset = media.viewPadding.bottom > 0
        ? media.viewPadding.bottom
        : media.padding.bottom;
    final isTablet = screenW >= 1000;
    final bottomSpace = bottomInset + (isTablet ? 24.0 : 18.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: isTablet ? 280 : 190,
                height: isTablet ? 280 : 190,
                decoration: BoxDecoration(
                  color: AppColores.primary.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: Container(
                width: isTablet ? 300 : 220,
                height: isTablet ? 300 : 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF66A3FF).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: isTablet ? 36 : 22,
                right: isTablet ? 36 : 22,
                top: isTablet ? 18 : 12,
                bottom: _getBottomPadding(context),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(height: isTablet ? 55 : 45),
                    Text(
                    'Buscando taxi...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 40 : 30,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF121826),
                    ),
                  ),
                  SizedBox(height: isTablet ? 35 : 25),
                  _buildSonarMap(isTablet),
                  SizedBox(height: isTablet ? 30 : 25),
                  Text(
                    'Estamos rastreando conductores en tiempo real para asignarte el mas cercano.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF5E6A7A),
                      fontSize: isTablet ? 18 : 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: isTablet ? 30 : 22),

                   Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 12,
                        vertical: isTablet ? 8 : 6,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Text(
                          //   _formatDuration(_searchSeconds),
                          //   textAlign: TextAlign.center,
                          //   style: TextStyle(
                          //     fontSize: isTablet ? 40 : 45,
                          //     fontWeight: FontWeight.w800,
                          //     foreground: ui.Paint()
                          //       ..style = ui.PaintingStyle.stroke
                          //       ..strokeWidth = isTablet ? 1 : 2
                          //       ..color = Colors.black,
                          //   ),
                          // ),
                          Text(
                            _formatDuration(_searchSeconds),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTablet ? 40 : 35,
                              fontWeight: FontWeight.w800,
                              color: AppColores.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 18 : 14),
                  _buildSearchingDots(isTablet),
                  
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _vm.isCancelling ? null : _cancelSolicitud,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.buttonPrimary,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 20 : 14,
                          vertical: isTablet ? 16 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: TextStyle(
                          fontSize: isTablet
                              ? 20
                              : ResponsiveHelper.sp(context, 15),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _vm.isCancelling
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: isTablet ? 20 : 16,
                                  height: isTablet ? 20 : 16,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('Cancelando...'),
                              ],
                            )
                          : const Text('Cancelar búsqueda'),
                    ),
                  ),
                  SizedBox(height: isTablet ? 8 : 4),
                  SizedBox(height: bottomSpace),
                ],
              ),
            ),
            // Center button to focus on client location (placed above the map)
            Positioned(
              right: 35,
              top: isTablet ? 230 : 140,
              child: SafeArea(
                child: FloatingActionButton(
                  heroTag: 'center_client',
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  onPressed: () {
                    if (_clientLocation == null) return;
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(_clientLocation!, 15),
                    );
                  },
                  child: const Icon(Icons.my_location, color: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSonarMap(bool isTablet) {
    final mapHeight = isTablet ? 250.0 : 450.0;
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: mapHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Builder(builder: (ctx) {
              final defaultIcon = BitmapDescriptor.defaultMarkerWithHue(widget.defaultMarkerHue);
              final combinedMarkers = <Marker>{
                for (final m in {..._taxiMarkers, ..._conectadosMarkers})
                  (m.icon == null) ? m.copyWith(iconParam: defaultIcon) : m,
              };

              return Mapagoogle(
                initialTarget: _clientLocation ?? _defaultCenter,
                initialZoom: 14,
                markers: combinedMarkers,
                circles: {
                  ..._sonarCircles,
                  ..._clientCircles,
                },
                onMapCreated: _onMapCreated,
                //myLocationEnabled: true,
                zoomGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchingDots(bool isTablet) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final phase = (_dotsController.value + (index * 0.2)) % 1.0;
            final active = phase < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: isTablet ? 12 : 10,
              height: isTablet ? 12 : 10,
              decoration: BoxDecoration(
                color: active
                    ? AppColores.buttonPrimary
                    : AppColores.buttonPrimary.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }

  double _getBottomPadding(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android) {
      // Detecta si hay barra de navegación usando MediaQuery
      final padding = MediaQuery.of(context).padding.bottom;
      // Si hay barra de navegación (padding > 0), deja el padding, si no, pon 0
      return padding > 0 ? padding : 0;
    } else {
      // En iOS, sin padding extra (SafeArea ya lo maneja)
      return 0;
    }
  }
}
