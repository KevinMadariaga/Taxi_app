import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';

/// Permite al cliente elegir un nuevo destino tocando el mapa. Hace
/// reverse-geocoding para obtener la dirección y actualiza el campo `destino`
/// del documento `solicitudes/{id}` en Firestore.
class CambiarDestinoView extends StatefulWidget {
  const CambiarDestinoView({
    super.key,
    required this.solicitudId,
    this.destinoInicial,
    this.direccionInicial = '',
  });

  final String solicitudId;
  final LatLng? destinoInicial;
  final String direccionInicial;

  @override
  State<CambiarDestinoView> createState() => _CambiarDestinoViewState();
}

class _CambiarDestinoViewState extends State<CambiarDestinoView> {
  static const LatLng _fallback = LatLng(8.2595534, -73.353469);

  GoogleMapController? _mapaController;
  LatLng? _seleccion;
  String _direccion = '';
  bool _geocodificando = false;
  bool _guardando = false;
  bool _cargandoUbicacion = false;

  @override
  void initState() {
    super.initState();
    _seleccion = widget.destinoInicial;
    _direccion = widget.direccionInicial;
  }

  @override
  void dispose() {
    _mapaController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapaController = controller;
    final destino = widget.destinoInicial;
    if (destino != null) {
      _mapaController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: destino, zoom: 15.5),
        ),
      );
    }
  }

  Future<void> _centrarEnUbicacionActual() async {
    if (_cargandoUbicacion || _mapaController == null) return;
    
    setState(() => _cargandoUbicacion = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
      
      final ubicacion = LatLng(pos.latitude, pos.longitude);
      await _mapaController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: ubicacion, zoom: 15.5),
        ),
      );
      
      if (!mounted) return;
      setState(() => _cargandoUbicacion = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoUbicacion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo obtener tu ubicación: $e')),
      );
    }
  }

  Future<void> _onTapMapa(LatLng pos) async {
    setState(() {
      _seleccion = pos;
      _geocodificando = true;
      _direccion = '';
    });
    try {
      final marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      final dir = marks.isNotEmpty ? _formatPlacemark(marks.first) : '';
      setState(() {
        _direccion = dir;
        _geocodificando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _direccion = '';
        _geocodificando = false;
      });
    }
  }

  String _formatPlacemark(Placemark p) {
    final partes = <String>[
      if ((p.street ?? '').isNotEmpty) p.street!,
      if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
      if ((p.locality ?? '').isNotEmpty) p.locality!,
    ];
    return partes.join(', ');
  }

  Future<void> _confirmar() async {
    final sel = _seleccion;
    if (sel == null || _guardando) return;
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .set({
            'destino': {
              'lat': sel.latitude,
              'lng': sel.longitude,
              'direccion': _direccion,
            },
            'destinoDireccion': _direccion,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destino actualizado')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _seleccion ?? widget.destinoInicial ?? _fallback;
    final markers = <Marker>{
      if (_seleccion != null)
        Marker(
          markerId: const MarkerId('nuevo_destino'),
          position: _seleccion!,
          draggable: true,
          onDragEnd: _onTapMapa,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
        title: const Text(
          'Cambiar dirección destino',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Mapagoogle(
              initialTarget: target,
              initialZoom: 15.5,
              markers: markers,
              myLocationEnabled: true,
              onTap: _onTapMapa,
              onMapCreated: _onMapCreated,
              padding: const EdgeInsets.only(bottom: 220),
            ),
          ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_rounded, color: AppColores.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Toca el mapa para elegir tu nuevo destino.',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 80,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: AppColores.primary,
              onPressed: _cargandoUbicacion ? null : _centrarEnUbicacionActual,
              child: _cargandoUbicacion
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColores.primary),
                      ),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _PanelConfirmacion(
              direccion: _direccion,
              geocodificando: _geocodificando,
              guardando: _guardando,
              habilitado: _seleccion != null,
              onConfirmar: _confirmar,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelConfirmacion extends StatelessWidget {
  const _PanelConfirmacion({
    required this.direccion,
    required this.geocodificando,
    required this.guardando,
    required this.habilitado,
    required this.onConfirmar,
  });

  final String direccion;
  final bool geocodificando;
  final bool guardando;
  final bool habilitado;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nuevo destino',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColores.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, color: AppColores.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: geocodificando
                      ? const Text(
                          'Obteniendo dirección...',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColores.textSecondary,
                          ),
                        )
                      : Text(
                          direccion.isNotEmpty
                              ? direccion
                              : (habilitado
                                    ? 'Ubicación seleccionada'
                                    : 'Sin destino seleccionado'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColores.textPrimary,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (!habilitado || guardando) ? null : onConfirmar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.buttonPrimary,
                  foregroundColor: AppColores.textWhite,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: guardando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColores.textWhite,
                        ),
                      )
                    : const Text(
                        'Confirmar destino',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
