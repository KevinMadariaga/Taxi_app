import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import 'package:provider/provider.dart';

import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccion_destino_screen.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccionar_ubicacion_mapa_view.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/transicion_pagina.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';

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

  Future<void> _ajustarOrigen() async {
    final origenActual = _vm.origen;
    final resultado = await Navigator.of(context)
        .push<SeleccionUbicacionResult>(
          transicionSuave(
            SeleccionarUbicacionMapaView(
              ubicacionInicial: origenActual.position,
              titulo: 'Ajusta tu ubicación en el mapa',
              direccionInicial: origenActual.title ?? origenActual.subtitle,
            ),
          ),
        );
    if (resultado == null || !mounted) return;
    await _vm.actualizarOrigen(
      resultado.position,
      direccionResuelta: resultado.direccion,
    );
  }

  Future<void> _ajustarDestino() async {
    final destinoActual = _vm.destino;
    final resultado = await Navigator.of(context)
        .push<SeleccionUbicacionResult>(
          transicionSuave(
            SeleccionarUbicacionMapaView(
              ubicacionInicial: destinoActual.position,
              titulo: 'Ajusta tu destino en el mapa',
              direccionInicial: destinoActual.title ?? destinoActual.subtitle,
            ),
          ),
        );
    if (resultado == null || !mounted) return;
    await _vm.actualizarDestino(
      resultado.position,
      direccionResuelta: resultado.direccion,
    );
  }

  void _onSolicitudCreada(String solicitudId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuscandoTaxiView(
          solicitudId: solicitudId,
          initialClientLocation: _vm.origen.position,
        ),
      ),
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
                SizedBox(height: 8.h),
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.04,
        ),
        child: const SizedBox(width: double.infinity, child: MapaRutaCard()),
      ),
    );
  }
}

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
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.wp(context, 4),
            12,
            ResponsiveHelper.wp(context, 4),
            ResponsiveHelper.hp(context, 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: palette.grey300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              RutaParadasCard(
                origen: vm.resolviendoDireccionOrigen
                    ? 'Buscando tu ubicación…'
                    : (vm.direccionOrigen ?? vm.origen.title ?? 'Ubicación'),
                destino: vm.destino.title ?? vm.destino.subtitle ?? 'Destino',
                onEditarOrigen: onAjustarOrigen,
                onEditarDestino: onAjustarDestino,
              ),
              const SizedBox(height: 10),
              const OpcionesViajeRow(),
              const SizedBox(height: 12),
              ConfirmarSolicitudSubmitBar(onSolicitudCreada: onSolicitudCreada),
            ],
          ),
        ),
      ),
    );
  }
}
