import 'package:flutter/material.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';

import 'dart:async';
import 'package:provider/provider.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;

  const BuscandoTaxiView({Key? key, this.solicitudId}) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView> {
  late final BuscandoTaxiViewModel _vm;

  static const Duration _loaderTransitionDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
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

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: _loaderTransitionDuration,
        pageBuilder: (_, __, ___) => LoaderMapaView(solicitudId: solicitudId),
      ),
    );
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  Future<void> _cancelSolicitud() async {
    if (_vm.isCancelling) return;

    await _vm.cancelarSolicitud();
    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => InicioClienteView()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    final double iconSize = isTablet ? screenW * 0.18 : 72;
    final double buttonWidth = isTablet
        ? screenW * 0.5
        : ResponsiveHelper.wp(context, 35);
    final double buttonHeight = isTablet
        ? 64
        : ResponsiveHelper.wp(context, 12);
    final double titleFontSize = isTablet ? 32 : 25;
    final double descFontSize = isTablet ? 18 : 14;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.wp(context, 4)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isTablet ? 32 : 24),
              Icon(Icons.local_taxi, size: iconSize, color: Colors.black87),
              SizedBox(height: isTablet ? 32 : 24),
              Text(
                'Buscando taxi',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isTablet ? 22 : 16),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 64.0 : 24.0,
                ),
                child: Text(
                  'Estamos buscando un conductor disponible. Esto puede tardar algunos segundos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: descFontSize,
                  ),
                ),
              ),
              SizedBox(height: isTablet ? 32 : 24),
              SizedBox(height: isTablet ? 48 : 36),
              Center(
                child: SizedBox(
                  width: buttonWidth,
                  height: buttonHeight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colores.amarillo,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _vm.isCancelling ? null : _cancelSolicitud,
                    child: _vm.isCancelling
                        ? SizedBox(
                            width: ResponsiveHelper.sp(context, 18),
                            height: ResponsiveHelper.sp(context, 18),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black87,
                            ),
                          )
                        : Text(
                            'Cancelar',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: isTablet
                                  ? 22
                                  : ResponsiveHelper.sp(context, 18),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pantalla intermedia que muestra el loader de mapa durante 2 segundos
/// antes de navegar a la vista de ruta del cliente.
class LoaderMapaView extends StatefulWidget {
  final String solicitudId;

  const LoaderMapaView({Key? key, required this.solicitudId}) : super(key: key);

  @override
  State<LoaderMapaView> createState() => _LoaderMapaViewState();
}

class _LoaderMapaViewState extends State<LoaderMapaView>
    with SingleTickerProviderStateMixin {
  Timer? _navigationTimer;
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _goToRouteAfterDelay();
  }

  void _goToRouteAfterDelay() {
    _navigationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => Rutaclienteviewmodel(),
            child: RutaCliente(idSolicitud: widget.solicitudId),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _dotsController.dispose();
    super.dispose();
  }

  Widget _animatedDot(int index) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (_, __) {
        final phase = (_dotsController.value + (index * 0.2)) % 1.0;
        final active = phase < 0.5;
        final opacity = active ? 1.0 : 0.35;
        final scale = active ? 1.0 : 0.85;

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColores.buttonPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: SafeArea(
        child: Center(
          child: Container(
            width: isTablet ? 520 : 320,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColores.buttonPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Conductor encontrado',
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Preparando tu ruta y detalles del viaje...',
                  style: TextStyle(
                    fontSize: isTablet ? 16 : 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _animatedDot(0),
                    const SizedBox(width: 8),
                    _animatedDot(1),
                    const SizedBox(width: 8),
                    _animatedDot(2),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
