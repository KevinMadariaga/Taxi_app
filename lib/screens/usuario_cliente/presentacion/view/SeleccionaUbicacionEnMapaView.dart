import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

/// Vista para seleccionar una ubicación en el mapa.
class SeleccionaUbicacionEnMapaView extends StatefulWidget {
  final LatLng ubicacionInicial;
  final String? titulo;
  final String? direccionInicial;

  const SeleccionaUbicacionEnMapaView({
    super.key,
    required this.ubicacionInicial,
    this.titulo,
    this.direccionInicial,
  });

  @override
  State<SeleccionaUbicacionEnMapaView> createState() =>
      _SeleccionaUbicacionEnMapaViewState();
}

class _SeleccionaUbicacionEnMapaViewState
    extends State<SeleccionaUbicacionEnMapaView> {
  late LatLng _center;
  GoogleMapController? _mapController;
  String _direccion = '';
  bool _isResolviendoDireccion = false;
  int _requestToken = 0;
  final Map<String, String> _direccionCache = <String, String>{};
  Timer? _idleDebounce;
  LatLng? _ultimaCoordConsultada;
  bool _contenidoVisible = false;

  @override
  void initState() {
    super.initState();
    _center = widget.ubicacionInicial;
    _ultimaCoordConsultada = _center;
    final initialAddress = widget.direccionInicial?.trim() ?? '';
    if (initialAddress.isNotEmpty) {
      _direccion = initialAddress;
      _direccionCache[_keyFromPoint(_center)] = initialAddress;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _contenidoVisible = true;
      });
    });
    if (initialAddress.isEmpty) {
      unawaited(_actualizarDireccion(_center));
    }
  }

  String _keyFromPoint(LatLng coord) {
    return '${coord.latitude.toStringAsFixed(5)},${coord.longitude.toStringAsFixed(5)}';
  }

  bool _seMovioLoSuficiente(LatLng a, LatLng b) {
    const umbral = 0.00005;
    return (a.latitude - b.latitude).abs() > umbral ||
        (a.longitude - b.longitude).abs() > umbral;
  }

  Future<void> _actualizarDireccion(LatLng coord) async {
    final key = _keyFromPoint(coord);
    final cached = _direccionCache[key];
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      if (_direccion == cached && !_isResolviendoDireccion) return;
      setState(() {
        _direccion = cached;
        _isResolviendoDireccion = false;
      });
      return;
    }

    final int currentToken = ++_requestToken;
    if (mounted && !_isResolviendoDireccion) {
      setState(() {
        _isResolviendoDireccion = true;
      });
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        coord.latitude,
        coord.longitude,
      );

      if (!mounted || currentToken != _requestToken) return;

      String direccion = '';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
      }

      final resolved = direccion.isNotEmpty
          ? direccion
          : '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
      _direccionCache[key] = resolved;

      if (_direccion == resolved && _isResolviendoDireccion == false) return;
      setState(() {
        _direccion = resolved;
        _isResolviendoDireccion = false;
      });
    } catch (_) {
      if (!mounted || currentToken != _requestToken) return;
      final fallback =
          '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
      if (_direccion == fallback && _isResolviendoDireccion == false) return;
      setState(() {
        _direccion = fallback;
        _isResolviendoDireccion = false;
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onCameraMove(CameraPosition position) {
    _center = position.target;
  }

  void _onCameraIdle() {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 180), () {
      final ultima = _ultimaCoordConsultada;
      if (ultima != null && !_seMovioLoSuficiente(ultima, _center)) {
        return;
      }
      _ultimaCoordConsultada = _center;
      unawaited(_actualizarDireccion(_center));
    });
  }

  void _onConfirmarUbicacion() {
    Navigator.of(context).pop(_center);
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Builder(
          builder: (context) {
            final screenW = MediaQuery.of(context).size.width;
            final double titleFontSize = (screenW / 390 * 18).clamp(15, 26);
            return Text(
              widget.titulo ?? 'Selecciona ubicación',
              style: TextStyle(fontSize: titleFontSize, color: Colors.black87),
            );
          },
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool compact = constraints.maxHeight < 620;

            return Column(
              children: [
                SizedBox(height: compact ? 8 : 12),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.of(context).size.width * 0.04,
                        vertical: compact ? 6 : 10,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 160),
                        child: SizedBox(
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Mapagoogle(
                                    initialTarget: _center,
                                    initialZoom: 16,
                                    onMapCreated: _onMapCreated,
                                    onCameraMove: _onCameraMove,
                                    onCameraIdle: _onCameraIdle,
                                    myLocationEnabled: true,
                                    myLocationButtonEnabled: true,
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
                    ),
                  ),
                ),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: _contenidoVisible
                      ? Offset.zero
                      : const Offset(0, 0.08),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: _contenidoVisible ? 1 : 0,
                    child: Column(
                      children: [
                        SizedBox(height: compact ? 10 : 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0),
                          child: Text(
                            'Mueve el mapa para seleccionar la ubicación',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18.0),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.amber,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  children: [
                                    if (_isResolviendoDireccion)
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    if (_isResolviendoDireccion)
                                      const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _direccion.isNotEmpty
                                            ? _direccion
                                            : 'Buscando dirección...',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Colors.black87,
                                        ),
                                        maxLines: compact ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16.0,
                            compact ? 4.0 : 8.0,
                            16.0,
                            compact ? 14.0 : 24.0,
                          ),
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
                              onPressed: _onConfirmarUbicacion,
                              child: const Text(
                                'Confirmar ubicación',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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
    );
  }
}
