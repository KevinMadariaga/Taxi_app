import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/caracteristicas/disponibilidad_conductores/presentacion/aviso_disponibilidad_en_vivo.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/editar_ubicacion_screen.dart';
import 'package:taxi_app/core/modelos/vehicle_type.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccion_destino_screen.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccionar_ubicacion_mapa_view.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/transicion_pagina.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/core/modelos/location_model.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';

import '../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'widgets/confirmar_solicitud_submit_bar.dart';
import 'widgets/mapa_ruta_card.dart';
import 'widgets/opciones_viaje_row.dart';
import 'widgets/ruta_paradas_card.dart';

/// Pantalla "Confirmar solicitud": mapa con origen+destino, tarifa, método
/// de pago y comentario. Único punto de entrada para crear una solicitud de
/// viaje — reemplaza a la vista legacy `MapPreview`/`DetailsSolicitud.dart`.
class ConfirmarSolicitudView extends StatefulWidget {
  const ConfirmarSolicitudView({
    super.key,
    required this.origen,
    required this.destino,
  });

  final LocationModel origen;
  final LocationModel destino;

  @override
  State<ConfirmarSolicitudView> createState() => _ConfirmarSolicitudViewState();
}

class _ConfirmarSolicitudViewState extends State<ConfirmarSolicitudView>
    with WidgetsBindingObserver {
  late final ConfirmarSolicitudViewModel _vm;
  bool _wasInBackground = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vm = ConfirmarSolicitudViewModel(
      origenInicial: widget.origen,
      destinoInicial: widget.destino,
    );
    _vm.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _wasInBackground = true;
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_wasInBackground) {
        _wasInBackground = false;
        final pausedAt = _pausedAt ?? DateTime.now();
        if (_vm.shouldReloadOnResume(pausedAt, DateTime.now())) {
          _vm.init();
        }
        _pausedAt = null;
      }
    }
  }

  Future<void> _handleBackNavigation() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final popped = await navigator.maybePop();
    if (popped || !mounted) return;

    await navigator.pushReplacement(
      transicionSuave(
        SeleccionDestinoScreen(currentLocation: _vm.origen.position),
      ),
    );
  }

  /// Cambiar recogida o destino: buscar por texto, pegar una ubicación de
  /// un chat o elegir en el mapa; lo elegido se confirma en el mapa.
  Future<SeleccionUbicacionResult?> _buscarYConfirmar({
    required LocationModel actual,
    required String titulo,
    required String etiquetaCampo,
    required String tituloMapa,
  }) {
    return Navigator.of(context).push<SeleccionUbicacionResult>(
      transicionSuave(
        EditarUbicacionScreen(
          actual: actual,
          cercaDe: _vm.origen.position,
          titulo: titulo,
          etiquetaCampo: etiquetaCampo,
          tituloMapa: tituloMapa,
        ),
      ),
    );
  }

  Future<void> _ajustarOrigen() async {
    final resultado = await _buscarYConfirmar(
      actual: _vm.origen,
      titulo: '¿Dónde te recogemos?',
      etiquetaCampo: 'Punto de recogida',
      tituloMapa: 'Confirma el punto de recogida',
    );
    if (resultado == null || !mounted) return;
    await _vm.actualizarOrigen(
      resultado.position,
      direccionResuelta: resultado.direccion,
    );
  }

  Future<void> _ajustarDestino() async {
    final resultado = await _buscarYConfirmar(
      actual: _vm.destino,
      titulo: 'Cambia tu destino',
      etiquetaCampo: 'Tu destino',
      tituloMapa: 'Confirma tu destino',
    );
    if (resultado == null || !mounted) return;
    await _vm.actualizarDestino(
      resultado.position,
      direccionResuelta: resultado.direccion,
    );
  }

  void _onSolicitudCreada(String solicitudId) {
    Navigator.of(context).pushNamed(
      RutasApp.buscandoTaxi,
      arguments: {
        'solicitudId': solicitudId,
        'initialClientLocation': _vm.origen.position,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ConfirmarSolicitudViewModel>.value(
      value: _vm,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: false,
        backgroundColor: context.palette.background,
        appBar: appBarNeutra(
          context,
          titulo: 'Detalle de la solicitud',
          leading: IconButton(
            tooltip: 'Atrás',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBackNavigation,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Expanded(child: _MapaSection()),
                // El panel toma el alto de su contenido y el mapa el resto:
                // con un porcentaje fijo de pantalla la información no
                // cabía completa en teléfonos chicos. Tope del 65% para
                // pantallas muy bajas (ahí el panel se desplaza por dentro).
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.65,
                  ),
                  child: _BottomContent(
                    onAjustarOrigen: _ajustarOrigen,
                    onAjustarDestino: _ajustarDestino,
                    onSolicitudCreada: _onSolicitudCreada,
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

class _MapaSection extends StatelessWidget {
  const _MapaSection();

  /// Llena todo el alto que deja el panel: centrado con su alto propio
  /// dejaba una franja vacía arriba y otra abajo.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (MediaQuery.sizeOf(context).width * 0.04).clamp(12.0, 24.0),
      ),
      child: const SizedBox.expand(child: MapaRutaCard()),
    );
  }
}

/// Ancho a partir del cual el panel deja de crecer (tablet, horizontal).
const double _anchoMaximoPanel = 640;

class _BottomContent extends StatelessWidget {
  const _BottomContent({
    required this.onAjustarOrigen,
    required this.onAjustarDestino,
    required this.onSolicitudCreada,
  });

  final VoidCallback onAjustarOrigen;
  final VoidCallback onAjustarDestino;
  final ValueChanged<String> onSolicitudCreada;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();

    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        // En tablet el panel no se estira de borde a borde: los botones y
        // las tarjetas a 1000 px de ancho se leen mal.
        // `heightFactor: 1`: centra a lo ancho pero mide lo que su contenido.
        // Sin él, `Center` tomaba todo el alto permitido (65%) y dejaba un
        // hueco entre el mapa y la tarjeta de recogida.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _anchoMaximoPanel),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final margen = (constraints.maxWidth * 0.04).clamp(12.0, 24.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: palette.grey300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    // Lo informativo se desplaza; la acción no: "Buscar
                    // conductor" queda siempre a la vista, abajo.
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: margen),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            RutaParadasCard(
                              origen: vm.resolviendoDireccionOrigen
                                  ? 'Buscando tu ubicación…'
                                  : (vm.direccionOrigen ??
                                        vm.origen.title ??
                                        'Ubicación'),
                              destino:
                                  vm.destino.title ??
                                  vm.destino.subtitle ??
                                  'Destino',
                              onEditarOrigen: onAjustarOrigen,
                              onEditarDestino: onAjustarDestino,
                            ),
                            const SizedBox(height: 8),
                            const OpcionesViajeRow(),
                            AvisoDisponibilidadEnVivo(
                              lat: vm.origen.position.latitude,
                              lng: vm.origen.position.longitude,
                              esMoto: vm.tipoVehiculo == VehicleType.moto,
                              onCambiarVehiculo: (moto) => vm.setTipoVehiculo(
                                moto ? VehicleType.moto : VehicleType.carro,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(margen, 10, margen, 8),
                      child: ConfirmarSolicitudSubmitBar(
                        onSolicitudCreada: onSolicitudCreada,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
