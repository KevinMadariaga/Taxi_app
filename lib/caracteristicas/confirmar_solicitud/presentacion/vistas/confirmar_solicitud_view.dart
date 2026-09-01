import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import 'package:provider/provider.dart';

import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccion_destino_screen.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/vistas/seleccionar_ubicacion_mapa_view.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/utils/transicion_pagina.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';

import '../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'widgets/confirmar_solicitud_submit_bar.dart';
import 'widgets/mapa_ruta_card.dart';
import 'widgets/metodo_pago_card.dart';
import 'widgets/ubicacion_info_card.dart';

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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            backgroundColor: AppColores.surface.withValues(alpha: 0.95),
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'Detalle de la solicitud',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: _handleBackNavigation,
            ),
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final resp = ResponsiveHelper.getResponsiveData(context);
              // Bajado desde 45/33/27: el selector de vehículo (que ocupaba
              // esta tarjeta) se movió a la modal de "Buscar conductor", así
              // que la tarjeta de abajo necesita menos alto — el que sobra
              // se lo queda el mapa.
              double bottomPct;
              if (resp.deviceType == DeviceType.mobile) {
                bottomPct = 38.0;
              } else if (resp.deviceType == DeviceType.tablet) {
                bottomPct = 28.0;
              } else {
                bottomPct = 23.0;
              }

              final double bottomHeight = ResponsiveHelper.hp(
                context,
                bottomPct,
              ).clamp(140.0, constraints.maxHeight * 0.65).toDouble();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 8.h),
                  const Expanded(child: _MapaSection()),
                  SizedBox(
                    height: bottomHeight,
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

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.wp(context, 4),
              ResponsiveHelper.hp(context, 1.2),
              ResponsiveHelper.wp(context, 4),
              ResponsiveHelper.hp(context, 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UbicacionInfoCard(
                  header: 'Tu ubicación actual',
                  value: vm.resolviendoDireccionOrigen
                      ? 'Buscando ubicación actual...'
                      : (vm.direccionOrigen ?? vm.origen.title ?? 'Ubicación'),
                  icon: Icons.place,
                  iconColor: Colors.blue,
                  iconBorderColor: Colores.azul,
                  cardBorderColor: Colors.blue,
                  cardBorderRadius: ResponsiveHelper.wp(context, 4),
                  onTap: onAjustarOrigen,
                ),
                SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                UbicacionInfoCard(
                  header: '¿Adónde va?',
                  value: vm.destino.title ?? vm.destino.subtitle ?? 'Destino',
                  icon: Icons.place,
                  iconColor: Colors.red,
                  iconBorderColor: Colors.red,
                  cardBorderColor: Colors.red,
                  cardBorderRadius: ResponsiveHelper.wp(context, 3),
                  onTap: onAjustarDestino,
                ),
                SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                const MetodoPagoCard(),
                SizedBox(height: ResponsiveHelper.hp(context, 0.8)),
                ConfirmarSolicitudSubmitBar(
                  onSolicitudCreada: onSolicitudCreada,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
