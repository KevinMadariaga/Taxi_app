import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;

  const BuscandoTaxiView({Key? key, this.solicitudId}) : super(key: key);

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
  double _sonarRadius = 120.0;
  Timer? _sonarTimer;
  final LatLng _defaultCenter = const LatLng(
    8.2595534,
    -73.353469,
  ); // centro (ejemplo)
  LatLng? _clientLocation;
  Set<Marker> _taxiMarkers = {};
  Set<Circle> _sonarCircles = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _conductoresSub;

  @override
  void initState() {
    super.initState();
    _initializeSonarMap();

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
    _initClientLocation();
    _subscribeConductores();

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
        _sonarRadius += 8;
        if (_sonarRadius > 220) {
          _sonarRadius = 120;
        }
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
      });
    });
  }

  Future<void> _loadTaxiIcon() async {
    try {
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(20, 20)),
        'assets/img/taxi_icon.png',
      );
      _taxiIcon = icon;
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

  Future<void> _initClientLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _clientLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_clientLocation!, 14),
      );
    } catch (_) {
      // No se pudo obtener, se queda en default
    }
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

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_clientLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_clientLocation!, 14),
      );
    }
  }

  @override
  void dispose() {
    _conductoresSub?.cancel();
    _sonarTimer?.cancel();
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
                  const Spacer(),
                  SizedBox(height: isTablet ? 50 : 38),
                  // Taxi animation centered
                  Center(
                    child: SizedBox(
                      width: isTablet ? 250 : 190,
                      height: isTablet ? 250 : 190,
                      child: lottie.Lottie.asset(
                        'assets/gif/car.json',
                        repeat: true,
                        animate: true,
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 25 : 15),
                  Text(
                    'Buscando un taxi...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 34 : 27,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF121826),
                    ),
                  ),
                  SizedBox(height: isTablet ? 14 : 10),
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

                  _buildSonarMap(isTablet),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSonarMap(bool isTablet) {
    final mapHeight = isTablet ? 190.0 : 150.0;
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
            child: Mapagoogle(
              initialTarget: _clientLocation ?? _defaultCenter,
              initialZoom: 14,
              markers: _taxiMarkers,
              circles: _sonarCircles,
              onMapCreated: _onMapCreated,
              myLocationEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
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
