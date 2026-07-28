import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SonarMapWidget
// Gestiona la animación del sonar y los marcadores del mapa de forma aislada,
// evitando que el timer de 350ms reconstruya el árbol principal.
//
// Extraído de buscando_taxi_view.dart (comunidad de menor cohesión del repo
// según graphify-out/GRAPH_REPORT.md, 0.02) — pieza autocontenida: no toca
// Firestore ni los timers de negocio de la pantalla, solo recibe props y
// dibuja. Riesgo mínimo de extracción.
// ─────────────────────────────────────────────────────────────────────────────

class SonarMapWidget extends StatefulWidget {
  const SonarMapWidget({
    super.key,
    required this.clientLocation,
    required this.conductoresPositions,
    required this.conectadosPositions,
    required this.isMoto,
    required this.ampliarRango,
    required this.mapHeight,
    required this.onMapCreated,
  });

  final LatLng? clientLocation;
  final Map<String, LatLng> conductoresPositions;
  final Map<String, LatLng> conectadosPositions;
  final bool isMoto;
  final bool ampliarRango;
  final double mapHeight;
  final void Function(GoogleMapController) onMapCreated;

  @override
  State<SonarMapWidget> createState() => _SonarMapWidgetState();
}

class _SonarMapWidgetState extends State<SonarMapWidget>
    with SingleTickerProviderStateMixin {
  static const _defaultCenter = LatLng(8.2595534, -73.353469);
  // Anillos concéntricos desfasados en el tiempo (estilo Uber/Didi): cada uno
  // expande y se desvanece; al estar desfasados, nunca se ve un "salto" o
  // reinicio brusco como con un único círculo que resetea su radio.
  static const _ringCount = 3;
  static const _ringCycleDuration = Duration(milliseconds: 2600);
  // Recalcular qué conductores conectados caen dentro del radio a un ritmo
  // bajo (no ligado a la animación visual, que corre a la frecuencia del
  // vsync): las posiciones de los conductores no cambian tan rápido y así
  // evitamos recomputar Sets de marcadores en cada frame.
  static const _driverVisibilityInterval = Duration(milliseconds: 900);

  GoogleMapController? _controller;

  BitmapDescriptor? _taxiIcon;
  BitmapDescriptor? _smallTaxiIcon;
  BitmapDescriptor? _bigTaxiIcon;
  BitmapDescriptor? _motoIcon;

  late final AnimationController _sonarController;
  // Radio máximo del sonar; se amplía tras 5 min sin encontrar conductor.
  double get _maxSonarRadius => widget.ampliarRango ? 1500.0 : 700.0;
  Timer? _driverVisibilityTimer;
  Set<Marker> _taxiMarkers = {};
  Set<Marker> _conectadosMarkers = {};
  final Set<String> _visibleConectadosIds = {};

  @override
  void initState() {
    super.initState();
    _loadTaxiIcon();
    _loadSmallTaxiIcon();
    _loadMotoIcon();

    _sonarController = AnimationController(
      vsync: this,
      duration: _ringCycleDuration,
    )..repeat();

    _updateVisibleConectadosMarkers();
    _driverVisibilityTimer = Timer.periodic(_driverVisibilityInterval, (_) {
      if (!mounted) return;
      setState(_updateVisibleConectadosMarkers);
    });
  }

  Future<void> _loadMotoIcon() async {
    try {
      _motoIcon = await MarkerIconHelper.fromIcon(
        Icons.two_wheeler_rounded,
        48,
        const Color(0xFF111111),
        circleBackground: true,
        backgroundColor: AppColores.primary,
        backgroundScale: 0.64,
        borderColor: Colors.white,
      );
      if (!mounted) return;
      _updateTaxiMarkers();
      _updateVisibleConectadosMarkers();
      setState(() {});
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_view');
    }
  }

  @override
  void didUpdateWidget(SonarMapWidget old) {
    super.didUpdateWidget(old);
    if (old.conductoresPositions != widget.conductoresPositions ||
        old.conectadosPositions != widget.conectadosPositions ||
        old.isMoto != widget.isMoto) {
      // _updateTaxiMarkers excluye los ids que ya están en conectadosPositions
      // (evita el ícono duplicado), así que también depende de ese mapa.
      _updateTaxiMarkers();
    }
    if (old.conectadosPositions != widget.conectadosPositions ||
        old.isMoto != widget.isMoto) {
      _updateVisibleConectadosMarkers();
    }
    if (old.clientLocation != widget.clientLocation) {
      _maybeRecenter(widget.clientLocation);
    }
  }

  // Última posición sobre la que se centró la cámara; evita re-centrar por
  // el ruido normal del GPS (variaciones de 1-3 m aun estando quieto), que
  // es justo lo que hacía parecer que "el sonar se mueve por todo el mapa":
  // cada micro-corrección de ubicación desplazaba el mapa bajo el overlay
  // fijo. El puntero del cliente debe verse clavado en su sitio.
  LatLng? _lastCenteredAt;
  static const _minRecenterMeters = 12.0;

  void _maybeRecenter(LatLng? loc) {
    if (loc == null) return;
    final last = _lastCenteredAt;
    if (last != null) {
      final moved = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        loc.latitude,
        loc.longitude,
      );
      if (moved < _minRecenterMeters) return;
    }
    _lastCenteredAt = loc;
    _controller?.animateCamera(CameraUpdate.newLatLng(loc));
  }

  @override
  void dispose() {
    _sonarController.dispose();
    _driverVisibilityTimer?.cancel();
    super.dispose();
  }

  // ── Marcadores de taxis disponibles ───────────────────────────────────────

  void _updateTaxiMarkers() {
    if (!mounted) return;
    final isMoto = widget.isMoto;
    if (!isMoto && _taxiIcon == null) {
      setState(() => _taxiMarkers = {});
      return;
    }
    final motoIcon =
        _motoIcon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    // `conductoresPositions` (usuarios/disponible) y `conectadosPositions`
    // (conductores_conectados) suelen traer al mismo conductor por ser
    // colecciones distintas para el mismo estado — sin este filtro salían
    // dos íconos superpuestos para un solo conductor real. El de conectados
    // ya se dibuja aparte (con animación de aparición), así que aquí se
    // excluye para no duplicarlo.
    final markers = widget.conductoresPositions.entries
        .where((e) => !widget.conectadosPositions.containsKey(e.key))
        .map((e) {
          return Marker(
            markerId: MarkerId('taxi_${e.key}'),
            position: e.value,
            icon: isMoto ? motoIcon : _taxiIcon!,
            infoWindow: InfoWindow(
              title: isMoto ? 'Moto cercana' : 'Taxi cercano',
            ),
          );
        })
        .toSet();
    setState(() => _taxiMarkers = markers);
  }

  // ── Marcadores de conductores conectados (filtrados por sonar) ────────────

  void _updateVisibleConectadosMarkers() {
    final center = widget.clientLocation ?? _defaultCenter;
    final isMoto = widget.isMoto;
    final visible = <Marker>{};
    final newVisibleIds = <String>{};

    for (final entry in widget.conectadosPositions.entries) {
      final id = entry.key;
      final pos = entry.value;
      final distance = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        pos.latitude,
        pos.longitude,
      );
      // El sonar visual barre en anillos hasta _maxSonarRadius; un conductor
      // "cerca" es cualquiera dentro de ese radio máximo (los anillos son
      // solo la animación, no un filtro de distancia variable en el tiempo).
      if (distance > _maxSonarRadius) continue;

      newVisibleIds.add(id);
      final isNew = !_visibleConectadosIds.contains(id);

      final icon = isMoto
          ? (_motoIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ))
          : (isNew
                ? (_bigTaxiIcon ??
                      _smallTaxiIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow,
                      ))
                : (_smallTaxiIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow,
                      )));

      visible.add(
        Marker(
          markerId: MarkerId('conectado_$id'),
          position: pos,
          icon: icon,
          infoWindow: InfoWindow(
            title: isMoto
                ? 'Conductor de moto conectado'
                : 'Conductor conectado',
          ),
        ),
      );

      // Después de un breve instante, reducir el ícono al tamaño pequeño
      // (usa la posición MÁS RECIENTE del conductor al momento de disparar,
      // no la capturada 420ms atrás, para no "regresar" el marcador a una
      // posición vieja si el conductor ya se movió).
      if (isNew) {
        Timer(const Duration(milliseconds: 420), () {
          if (!mounted) return;
          final latestPos = widget.conectadosPositions[id] ?? pos;
          final smallIcon = isMoto
              ? (_motoIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ))
              : (_smallTaxiIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueYellow,
                    ));
          setState(() {
            _conectadosMarkers = {
              ..._conectadosMarkers.where(
                (m) => m.markerId.value != 'conectado_$id',
              ),
              Marker(
                markerId: MarkerId('conectado_$id'),
                position: latestPos,
                icon: smallIcon,
                infoWindow: InfoWindow(
                  title: isMoto
                      ? 'Conductor de moto conectado'
                      : 'Conductor conectado',
                ),
              ),
            };
          });
        });
      }
    }

    _visibleConectadosIds
      ..clear()
      ..addAll(newVisibleIds);

    // Reemplaza el set completo por el recién calculado: un solo marcador
    // por conductor (`markerId` = 'conectado_$id') en su posición ACTUAL.
    // Antes se mezclaba con marcadores "transitorios" del estado anterior
    // que, al tener distinta `position` pero el mismo `markerId`, Dart no
    // deduplicaba (Marker.hashCode solo usa markerId, pero `==` compara
    // también position) — quedaban ambos y el círculo del conductor se
    // "acumulaba" en cada ubicación por la que pasó en vez de moverse.
    _conectadosMarkers = visible;
  }

  // ── Carga de íconos ───────────────────────────────────────────────────────

  Future<void> _loadTaxiIcon() async {
    try {
      _taxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        48,
        const Color(0xFF111111),
        circleBackground: true,
        backgroundColor: AppColores.primary,
        backgroundScale: 0.64,
        borderColor: Colors.white,
      );
      if (!mounted) return;
      _updateTaxiMarkers();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_view');
    }
  }

  Future<void> _loadSmallTaxiIcon() async {
    try {
      _smallTaxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        42,
        const Color(0xFF111111),
        circleBackground: true,
        backgroundColor: AppColores.primary,
        backgroundScale: 0.64,
        borderColor: Colors.white,
      );
      if (!mounted) return;
      _bigTaxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        56,
        const Color(0xFF111111),
        circleBackground: true,
        backgroundColor: AppColores.primary,
        backgroundScale: 0.64,
        borderColor: Colors.white,
      );
      if (!mounted) return;
      setState(() {});
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_view');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = widget.clientLocation ?? _defaultCenter;
    return Container(
      width: double.infinity,
      height: widget.mapHeight,
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // El mapa solo lleva los marcadores reales (posición geográfica
            // de conductores). El radar NO se dibuja con Circle nativos:
            // animarlos a 60fps manda un mensaje por canal de plataforma a
            // Android/iOS en cada frame, y en Android eso es lo que causaba
            // el trabado. El radar es un dibujo 100% Flutter encima del mapa.
            Mapagoogle(
              initialTarget: center,
              initialZoom: 17.0,
              markers: {..._taxiMarkers, ..._conectadosMarkers},
              onMapCreated: (controller) {
                _controller = controller;
                _lastCenteredAt = center;
                widget.onMapCreated(controller);
              },
              // Pantalla puramente informativa ("buscando cerca de ti"): el
              // puntero no debe poder arrastrarse ni el mapa acercarse o
              // rotarse por gesto — toda interacción queda deshabilitada.
              zoomGesturesEnabled: false,
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
            // La cámara siempre está centrada en el cliente (ver
            // didUpdateWidget/onMapCreated), así que el overlay centrado en
            // el contenedor coincide visualmente con su ubicación real.
            IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _sonarController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _RadarPainter(
                        progress: _sonarController.value,
                        color: AppColores.primary,
                        ringCount: _ringCount,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dibuja el radar (anillos concéntricos que expanden y se desvanecen, más
/// el punto "tu ubicación" en el centro) en un solo pase de Canvas. Es pura
/// composición de Flutter/Skia — no pasa por el canal de plataforma del mapa,
/// así que animar a 60fps no tiene costo nativo ni en Android ni en iOS.
class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  final double progress;
  final Color color;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide * 0.42;

    for (var i = 0; i < ringCount; i++) {
      final phase = (progress + i / ringCount) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final radius = eased * maxRadius;
      final fade = (1.0 - phase).clamp(0.0, 1.0);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: fade * 0.10),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: fade * 0.6),
      );
    }

    // Halo suave + punto sólido con borde blanco: "estás aquí".
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.ringCount != ringCount;
}
