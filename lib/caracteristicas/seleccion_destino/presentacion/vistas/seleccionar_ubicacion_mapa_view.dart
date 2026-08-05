import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/boton.dart';

import '../viewmodels/seleccionar_ubicacion_mapa_viewmodel.dart';

export '../../dominio/entidades/seleccion_ubicacion_result.dart';

/// Vista para seleccionar/ajustar una ubicación moviendo el mapa: el pin
/// queda fijo en el centro de la pantalla y el usuario mueve el mapa debajo
/// hasta que el pin apunte al punto deseado.
class SeleccionarUbicacionMapaView extends StatelessWidget {
  const SeleccionarUbicacionMapaView({
    super.key,
    required this.ubicacionInicial,
    this.titulo,
    this.direccionInicial,
  });

  final LatLng ubicacionInicial;
  final String? titulo;
  final String? direccionInicial;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SeleccionarUbicacionMapaViewModel(
        ubicacionInicial: ubicacionInicial,
        direccionInicial: direccionInicial,
      ),
      child: _SeleccionarUbicacionMapaBody(titulo: titulo),
    );
  }
}

class _SeleccionarUbicacionMapaBody extends StatefulWidget {
  const _SeleccionarUbicacionMapaBody({this.titulo});

  final String? titulo;

  @override
  State<_SeleccionarUbicacionMapaBody> createState() =>
      _SeleccionarUbicacionMapaBodyState();
}

class _SeleccionarUbicacionMapaBodyState
    extends State<_SeleccionarUbicacionMapaBody> {
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SeleccionarUbicacionMapaViewModel>().mostrarContenido();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onConfirmar() {
    final vm = context.read<SeleccionarUbicacionMapaViewModel>();
    Navigator.of(context).pop(vm.confirmar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Builder(
          builder: (context) {
            final screenW = MediaQuery.of(context).size.width;
            final titleFontSize = (screenW / 390 * 18).clamp(15, 26);
            return Text(
              widget.titulo ?? 'Selecciona ubicación',
              style: TextStyle(
                fontSize: titleFontSize.toDouble(),
                color: AppColores.textPrimary,
              ),
            );
          },
        ),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.surface,
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
                          child: _MapaConPin(
                            onMapCreated: (c) => _mapController = c,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ContenidoInferior(compact: compact, onConfirmar: _onConfirmar),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta del mapa con el pin fijo en el centro geométrico del widget.
class _MapaConPin extends StatelessWidget {
  const _MapaConPin({required this.onMapCreated});

  final ValueChanged<GoogleMapController> onMapCreated;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SeleccionarUbicacionMapaViewModel>();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColores.textPrimary, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(
              child: Mapagoogle(
                // Zoom suficiente para distinguir la calle exacta, no solo
                // el barrio — el objetivo del picker es precisión de punto.
                initialTarget: vm.center,
                initialZoom: 17,
                onMapCreated: onMapCreated,
                onCameraMove: vm.onCameraMove,
                onCameraIdle: vm.onCameraIdle,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
              ),
            ),
            const IgnorePointer(child: _PinCentral()),
          ],
        ),
      ),
    );
  }
}

/// Pin fijo centrado en el mapa: la punta del ícono (marcada por el punto de
/// sombra debajo) queda exactamente sobre el centro real del `GoogleMap`,
/// que es la coordenada que efectivamente se confirma.
class _PinCentral extends StatelessWidget {
  const _PinCentral();

  static const double _pinSize = 44;
  static const double _gap = 2;
  static const double _sombraDiametro = 6;
  static const double _alturaTotal = _pinSize + _gap + _sombraDiametro;

  @override
  Widget build(BuildContext context) {
    // Se traslada el pin hacia arriba la mitad de su altura total: así el
    // punto de sombra (la referencia visual de a qué apunta el pin), que
    // nace en el borde inferior del widget, termina exactamente en el
    // centro del Stack — el mismo punto que usa GoogleMap como `target`.
    return Transform.translate(
      offset: const Offset(0, -_alturaTotal / 2),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: _pinSize, color: AppColores.primary),
          SizedBox(height: _gap),
          _SombraPin(),
        ],
      ),
    );
  }
}

class _SombraPin extends StatelessWidget {
  const _SombraPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _PinCentral._sombraDiametro,
      height: _PinCentral._sombraDiametro,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColores.overlayDark,
      ),
    );
  }
}

class _ContenidoInferior extends StatelessWidget {
  const _ContenidoInferior({required this.compact, required this.onConfirmar});

  final bool compact;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SeleccionarUbicacionMapaViewModel>();
    return AnimatedSlide(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      offset: vm.contenidoVisible ? Offset.zero : const Offset(0, 0.08),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: vm.contenidoVisible ? 1 : 0,
        child: Column(
          children: [
            SizedBox(height: compact ? 10 : 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Mueve el mapa para seleccionar la ubicación',
                style: TextStyle(fontSize: 16, color: AppColores.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: compact ? 10 : 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppColores.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        if (vm.resolviendoDireccion) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            vm.direccion.isNotEmpty
                                ? vm.direccion
                                : 'Buscando dirección...',
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColores.textPrimary,
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
                16,
                compact ? 4 : 8,
                16,
                compact ? 14 : 24,
              ),
              child: CustomButton(
                text: 'Confirmar ubicación',
                onPressed: onConfirmar,
                width: double.infinity,
                height: 56,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
