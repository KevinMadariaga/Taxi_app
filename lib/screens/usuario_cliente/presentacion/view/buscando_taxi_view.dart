import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isTablet = screenW >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: SafeArea(
        bottom: Theme.of(context).platform == TargetPlatform.android ? false : true,
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
              padding: EdgeInsets.only(
                left: isTablet ? 36 : 22,
                right: isTablet ? 36 : 22,
                top: isTablet ? 18 : 12,
                bottom: _getBottomPadding(context),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Spacer(),
                  // Taxi animation centered
                  Center(
                    child: SizedBox(
                      width: isTablet ? 220 : 140,
                      height: isTablet ? 220 : 140,
                      child: Lottie.asset(
                        'assets/gif/taxi.json',
                        repeat: true,
                        animate: true,
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
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
                  SizedBox(
                    width: double.infinity,
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
                                  width: isTablet ? 20 : 16,
                                  height: isTablet ? 20 : 16,
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
                  SizedBox(height: isTablet ? 8 : 4),
                ],
              ),
            ),
          ],
        ),
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

  double _getBottomPadding(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android) {
      // Detecta si hay barra de navegación usando MediaQuery
      final padding = MediaQuery.of(context).padding.bottom;
      // Si hay barra de navegación (padding > 0), deja el padding, si no, pon 0
      return padding > 0 ? padding : 0;
    } else {
      // En iOS, sin padding extra (SafeArea ya lo maneja)
      return 0;
    }
  }
}
