import 'package:flutter/material.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/RutaClienteViewModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:provider/provider.dart';

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;

  const BuscandoTaxiView({Key? key, this.solicitudId}) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView> {
  late final BuscandoTaxiViewModel _vm;

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

    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => ChangeNotifierProvider(
        create: (_) => Rutaclienteviewmodel(),
        child: RutaCliente(idSolicitud: solicitudId),
      ),
      title: 'Conductor encontrado',
      subtitle: 'Preparando tu ruta y detalles del viaje...',
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
