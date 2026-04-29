import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel, ContraofertaItem;
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;
  final double defaultMarkerHue;
  const BuscandoTaxiView({
    Key? key,
    this.solicitudId,
    this.defaultMarkerHue = BitmapDescriptor.hueYellow,
  }) : super(key: key);

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
  final Map<String, LatLng> _latestConductoresPositions = {};
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
  StreamSubscription<Map<String, LatLng>>? _conductoresSub;
  StreamSubscription<Map<String, LatLng>>? _conductoresConectadosSub;
  final Map<String, bool> _respondingOffer = {};

  @override
  void initState() {
    super.initState();
    _vm = BuscandoTaxiViewModel();
    _vm.addListener(_onVmChanged);
    _vm.iniciarEscucha(
      solicitudId: widget.solicitudId,
      onAsignada: _onSolicitudAsignada,
    );

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
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
    _updateTaxiMarkers();
    _updateVisibleConectadosMarkers();
  }

  String _formatCurrency(num value) {
    final asInt = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < asInt.length; i++) {
      final reverseIndex = asInt.length - i;
      buf.write(asInt[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buf.write('.');
      }
    }
    return buf.toString();
  }

  Future<void> _abrirModalEditarValor() async {
    String _formatInput(String raw) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return '';
      final parsed = int.tryParse(digits) ?? 0;
      return _formatCurrency(parsed);
    }

    final initialDigits = _vm.valorServicioActual > 0
        ? _vm.valorServicioActual.round().toString()
        : '10000';
    final initialFormatted = _formatInput(initialDigits);
    final controller = TextEditingController(text: initialFormatted)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialFormatted.length,
      );
    bool isFormatting = false;

    List<int> _buildSuggestions() {
      final current = int.tryParse(initialDigits) ?? 5000;
      final base = current < 5000 ? 5000 : current;
      return <int>[base + 500, base + 1000, base + 1500, base + 2000];
    }

    void _applySuggestion(int value) {
      final formatted = _formatCurrency(value);
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final keyboardInset = media.viewInsets.bottom;
        final bottomGap = keyboardInset > 0
            ? keyboardInset + 12
            : media.viewPadding.bottom + 12;

        return Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 12, bottomGap),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actualizar valor del servicio',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      if (isFormatting) return;
                      final formatted = _formatInput(value);
                      if (formatted == value) return;
                      isFormatting = true;
                      controller.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                      isFormatting = false;
                    },
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      hintText: 'Ej: 11.000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _buildSuggestions().map((value) {
                      return ActionChip(
                        label: Text(
                          '\$${_formatCurrency(value)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _applySuggestion(value),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _vm.isUpdatingValor
                          ? null
                          : () async {
                              final digits = controller.text.replaceAll(
                                RegExp(r'[^0-9]'),
                                '',
                              );
                              if (digits.isEmpty) return;
                              final next = double.tryParse(digits);
                              if (next == null || next <= 0) return;

                              final ok = await _vm.actualizarValorServicio(
                                next,
                              );
                              if (!mounted) return;
                              if (ok) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Valor actualizado, seguimos buscando conductor.',
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo actualizar el valor.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: _vm.isUpdatingValor
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar nuevo valor'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  Future<void> _aceptarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true) return;
    setState(() => _respondingOffer[conductorId] = true);
    final ok = await _vm.aceptarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    setState(() => _respondingOffer.remove(conductorId));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo aceptar la oferta.')),
      );
    }
  }

  Future<void> _rechazarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true) return;
    setState(() => _respondingOffer[conductorId] = true);
    final ok = await _vm.rechazarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    setState(() => _respondingOffer.remove(conductorId));
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo rechazar la oferta.')),
      );
    }
  }

  Widget _buildSonarMapWithOfertasOverlay(BuildContext context, bool isTablet) {
    final ofertas = _vm.contraofertas;
    if (ofertas.isEmpty) return _buildSonarMap(context);

    final resp = ResponsiveHelper.getResponsiveData(context);
    final device = resp.deviceType;
    double pct;
    if (device == DeviceType.mobile) {
      pct = 45.0;
    } else if (device == DeviceType.tablet) {
      pct = 35.0;
    } else {
      pct = 30.0;
    }
    final mapHeight = ResponsiveHelper.hp(context, pct).clamp(160.0, 700.0);

    return Stack(
      children: [
        _buildSonarMap(context),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Container(
              constraints: BoxConstraints(maxHeight: mapHeight * 0.65),
              color: Colors.black.withValues(alpha: 0.78),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppColores.buttonPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ofertas de conductores (${ofertas.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isTablet ? 15 : 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...ofertas.map((o) => _buildOfertaCard(o, isTablet)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfertaCard(ContraofertaItem oferta, bool isTablet) {
    final isResponding = _respondingOffer[oferta.conductorId] == true ||
        _vm.isRespondingCounteroffer;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.buttonPrimary, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Avatar del conductor
            CircleAvatar(
              radius: isTablet ? 26 : 22,
              backgroundColor: Colors.grey[200],
              backgroundImage: oferta.conductorFoto != null &&
                      oferta.conductorFoto!.isNotEmpty
                  ? NetworkImage(oferta.conductorFoto!)
                  : null,
              child: oferta.conductorFoto == null ||
                      oferta.conductorFoto!.isEmpty
                  ? Icon(Icons.person,
                      size: isTablet ? 28 : 24, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            // Nombre y placa
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    oferta.conductorNombre,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 15 : 13,
                      color: const Color(0xFF121826),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (oferta.placa != null && oferta.placa!.isNotEmpty)
                    Text(
                      oferta.placa!,
                      style: TextStyle(
                        fontSize: isTablet ? 13 : 11,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Precio y botones
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${_formatCurrency(oferta.valor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isTablet ? 18 : 16,
                    color: const Color(0xFF121826),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OfertaButton(
                      label: 'Rechazar',
                      color: Colors.grey[200]!,
                      textColor: Colors.black54,
                      isLoading: isResponding,
                      onTap: () => _rechazarOferta(oferta.conductorId),
                    ),
                    const SizedBox(width: 8),
                    _OfertaButton(
                      label: 'Aceptar',
                      color: AppColores.buttonPrimary,
                      textColor: Colors.black,
                      isLoading: isResponding,
                      onTap: () => _aceptarOferta(oferta.conductorId),
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
      _taxiIcon = await _bitmapDescriptorFromAsset(
        'assets/img/taxi_icon.png',
        40,
      );
      _updateTaxiMarkers();
    } catch (_) {
      // fallback si no existe el asset o hay error
    }
  }

  Future<void> _loadSmallTaxiIcon() async {
    try {
      // Create descriptors from bytes at explicit pixel widths so size changes take effect
      _smallTaxiIcon = await _bitmapDescriptorFromAsset(
        'assets/img/taxi_icon.png',
        42,
      );
      try {
        _bigTaxiIcon = await _bitmapDescriptorFromAsset(
          'assets/img/taxi_icon.png',
          42,
        );
      } catch (_) {}
      if (!mounted) return;
      _updateVisibleConectadosMarkers();
      setState(() {});
    } catch (_) {
      // ignore
    }
  }

  Future<BitmapDescriptor> _bitmapDescriptorFromAsset(
    String path,
    int targetWidth,
  ) async {
    final byteData = await rootBundle.load(path);
    final bytes = byteData.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );
    final frame = await codec.getNextFrame();
    final pngBytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
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
    _conductoresSub = _vm.streamConductoresDisponibles().listen(
      (positions) {
        if (!mounted) return;
        _latestConductoresPositions
          ..clear()
          ..addAll(positions);
        _updateTaxiMarkers();
      },
      onError: (_) {},
    );
  }

  void _updateTaxiMarkers() {
    if (!mounted) return;
    final isMoto = _vm.isMotoSolicitud;
    if (!isMoto && _taxiIcon == null) {
      setState(() {
        _taxiMarkers = {};
      });
      return;
    }

    final markers = _latestConductoresPositions.entries.map((e) {
      final id = e.key;
      final pos = e.value;
      return Marker(
        markerId: MarkerId('taxi_$id'),
        position: pos,
        icon: isMoto
            ? BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              )
            : _taxiIcon!,
        infoWindow: InfoWindow(
          title: isMoto ? 'Moto cercana' : 'Taxi cercano',
        ),
      );
    }).toSet();

    setState(() {
      _taxiMarkers = markers;
    });
  }

  void _subscribeConductoresConectados() {
    _conductoresConectadosSub?.cancel();
    _conductoresConectadosSub = _vm.streamConductoresConectados().listen(
      (positions) {
        if (!mounted) return;
        _allConectadosPositions
          ..clear()
          ..addAll(positions);
        _updateVisibleConectadosMarkers();
        setState(() {});
      },
      onError: (_) {},
    );
  }

  void _updateVisibleConectadosMarkers() {
    final center = _clientLocation ?? _defaultCenter;
    final isMoto = _vm.isMotoSolicitud;
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
          visible.add(
            Marker(
              markerId: MarkerId('conectado_$id'),
              position: pos,
              icon:
                  isMoto
                      ? BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueOrange,
                        )
                      : (_bigTaxiIcon ??
                          _smallTaxiIcon ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueYellow,
                          )),
              infoWindow: InfoWindow(
                title: isMoto
                    ? 'Conductor de moto conectado'
                    : 'Conductor conectado',
              ),
            ),
          );

          // schedule to shrink back to small icon after a short delay
          Timer(const Duration(milliseconds: 420), () {
            if (!mounted) return;
            _conectadosMarkers = {
              ..._conectadosMarkers.where(
                (m) => m.markerId.value != 'conectado_$id',
              ),
              Marker(
                markerId: MarkerId('conectado_$id'),
                position: pos,
                icon:
                    isMoto
                        ? BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueOrange,
                          )
                        : (_smallTaxiIcon ??
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueYellow,
                            )),
                infoWindow: InfoWindow(
                  title: isMoto
                      ? 'Conductor de moto conectado'
                      : 'Conductor conectado',
                ),
              ),
            };
            setState(() {});
          });
        } else {
          // already visible before, render with small icon
          visible.add(
            Marker(
              markerId: MarkerId('conectado_$id'),
              position: pos,
              icon:
                  isMoto
                      ? BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueOrange,
                        )
                      : (_smallTaxiIcon ??
                          BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueYellow,
                          )),
              infoWindow: InfoWindow(
                title: isMoto
                    ? 'Conductor de moto conectado'
                    : 'Conductor conectado',
              ),
            ),
          );
        }
      }
    }

    _visibleConectadosIds
      ..clear()
      ..addAll(newVisibleIds);

    // Merge visible with any transient markers currently in _conectadosMarkers
    // so brief pop icons are respected until they are replaced by the timer.
    final transient = _conectadosMarkers
        .where(
          (m) => newVisibleIds.contains(
            m.markerId.value.replaceFirst('conectado_', ''),
          ),
        )
        .toSet();
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
    final isTablet = screenW >= 1000;
    final _resp = ResponsiveHelper.getResponsiveData(context);
    final _scale = _resp.scale;

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
              padding: ResponsiveHelper.padding(
                context,
                left: isTablet ? 36 : 22,
                right: isTablet ? 36 : 22,
                top: isTablet ? 18 : 12,
              ).copyWith(bottom: _getBottomPadding(context)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(height: (isTablet ? 40 : 23) * _scale),
                  Text(
                    'Buscando taxi...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isTablet ? 40 : 30,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF121826),
                    ),
                  ),
                  SizedBox(height: (isTablet ? 35 : 25) * _scale),
                  _buildSonarMapWithOfertasOverlay(context, isTablet),
                  SizedBox(height: (isTablet ? 30 : 20) * _scale),
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
                  SizedBox(height: (isTablet ? 15 : 10) * _scale),
                  GestureDetector(
                    onTap:
                        _vm.isUpdatingValor ? null : _abrirModalEditarValor,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 16 : 12,
                        vertical: isTablet ? 12 : 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.edit,
                            size: isTablet ? 18 : 16,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Oferta actual: \$${_formatCurrency(_vm.valorServicioActual)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF121826),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: (isTablet ? 12 : 10) * _scale),
                  Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 12,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
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
                  SizedBox(height: (isTablet ? 18 : 14) * _scale),
                  _buildSearchingDots(isTablet),
                  SizedBox(height: (isTablet ? 18 : 14) * _scale),
                  SizedBox(
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
                                  width: (isTablet ? 20 : 16) * _scale,
                                  height: (isTablet ? 20 : 16) * _scale,
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
                  SizedBox(height: (isTablet ? 18 : 14) * _scale),
                ],
              ),
            ),
            // Center button to focus on client location (placed above the map)
            Positioned(
              right: (35) * _scale,
              top: (isTablet ? 230 : 140) * _scale,
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

  Widget _buildSonarMap(BuildContext context) {
    final resp = ResponsiveHelper.getResponsiveData(context);
    final device = resp.deviceType;

    // Height as percentage of screen height depending on device type
    double pct;
    if (device == DeviceType.mobile) {
      pct = 45.0; // mobile: 45% of screen height
    } else if (device == DeviceType.tablet) {
      pct = 35.0; // tablet: 35%
    } else {
      pct = 30.0; // desktop: 30%
    }

    double mapHeight = ResponsiveHelper.hp(context, pct);
    // clamp to sensible min/max to avoid extremely small/large maps
    mapHeight = mapHeight.clamp(160.0, 700.0);
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
            child: Builder(
              builder: (ctx) {
                // All Marker.icon are non-null, so just use the set directly
                final combinedMarkers = <Marker>{
                  ..._taxiMarkers,
                  ..._conectadosMarkers,
                };

                return Mapagoogle(
                  initialTarget: _clientLocation ?? _defaultCenter,
                  initialZoom: 14,
                  markers: combinedMarkers,
                  circles: {..._sonarCircles, ..._clientCircles},
                  onMapCreated: _onMapCreated,
                  //myLocationEnabled: true,
                  zoomGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                );
              },
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
      final padding = MediaQuery.of(context).padding.bottom;
      return padding > 0 ? padding : 0;
    } else {
      return 0;
    }
  }
}

// ── Widget auxiliar para botones Aceptar/Rechazar ─────────────────────────

class _OfertaButton extends StatelessWidget {
  const _OfertaButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isLoading ? Colors.grey[200] : color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black54,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}
