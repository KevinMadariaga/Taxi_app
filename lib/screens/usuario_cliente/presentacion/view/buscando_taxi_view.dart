import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking/views/trip_tracking_screen.dart';
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

  @override
  void initState() {
    super.initState();

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

  @override
  void dispose() {
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

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeClienteView()));
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: SafeArea(
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
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 36 : 22,
                vertical: isTablet ? 18 : 12,
              ),
              child: Column(
                children: [
                  const Spacer(),
                  _buildTaxiAnimation(isTablet),
                  SizedBox(height: isTablet ? 34 : 26),
                  Text(
                    'Buscando un taxi cerca de ti...',
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
                  SizedBox(height: isTablet ? 26 : 20),
                  _buildSearchingDots(isTablet),
                  const Spacer(),
                  TextButton(
                    onPressed: _vm.isCancelling ? null : _cancelSolicitud,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6A7382),
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 20 : 14,
                        vertical: isTablet ? 12 : 10,
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
                                  color: Color(0xFF6A7382),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Cancelando...',
                                style: TextStyle(
                                  fontSize: isTablet
                                      ? 20
                                      : ResponsiveHelper.sp(context, 15),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Cancelar busqueda',
                            style: TextStyle(
                              fontSize: isTablet
                                  ? 20
                                  : ResponsiveHelper.sp(context, 15),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  SizedBox(height: isTablet ? 8 : 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxiAnimation(bool isTablet) {
    return Container(
      width: double.infinity,
      height: isTablet ? 280 : 210,
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 20 : 14,
        vertical: isTablet ? 18 : 14,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDFEFF), Color(0xFFF1F6FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD8E4F4), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x15000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final taxiSize = isTablet ? 74.0 : 62.0;
          final taxiTravel = (constraints.maxWidth - taxiSize).clamp(
            10.0,
            double.infinity,
          );

          return AnimatedBuilder(
            animation: _taxiController,
            builder: (context, _) {
              final value = _taxiController.value;
              final taxiLeft = taxiTravel * value;
              final bob = math.sin(value * math.pi * 2) * (isTablet ? 4 : 3);

              return Stack(
                children: [
                  Positioned(
                    top: isTablet ? 14 : 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        final h = (index % 2 == 0)
                            ? (isTablet ? 32.0 : 24.0)
                            : (isTablet ? 24.0 : 18.0);
                        return Container(
                          width: isTablet ? 20 : 14,
                          height: h,
                          decoration: BoxDecoration(
                            color: const Color(0xFFBFD2E9).withOpacity(0.7),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    top: isTablet ? 150 : 116,
                    child: Container(
                      height: isTablet ? 14 : 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF253046),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    top: isTablet ? 156 : 121,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(8, (index) {
                        final phase = (value + (index * 0.13)) % 1.0;
                        final active = phase < 0.55;
                        return Opacity(
                          opacity: active ? 0.95 : 0.25,
                          child: Container(
                            width: isTablet ? 18 : 14,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Positioned(
                    left: taxiLeft,
                    top: (isTablet ? 98 : 78) + bob,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: taxiSize + 8,
                          height: taxiSize + 8,
                          decoration: BoxDecoration(
                            color: AppColores.primary.withOpacity(0.22),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(
                          Icons.local_taxi_rounded,
                          color: AppColores.buttonPrimary,
                          size: taxiSize,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: isTablet ? 10 : 6,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 12 : 9,
                        vertical: isTablet ? 7 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C8A52),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Buscando',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 14 : 11,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
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
}
