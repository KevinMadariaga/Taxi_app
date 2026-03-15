import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/InicioConductorViewModel.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/resumen_conductor_viewmodel.dart';

class ResumenConductorView extends StatelessWidget {
  final String solicitudId;
  const ResumenConductorView({super.key, required this.solicitudId});

  static String _thousands(String s) {
    final r = s.split('').reversed.toList();
    final out = <String>[];
    for (int i = 0; i < r.length; i++) {
      if (i != 0 && i % 3 == 0) out.add('.');
      out.add(r[i]);
    }
    return out.reversed.join();
  }

  static String _formatCurrency(dynamic v) {
    final num n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return '\$${_thousands(n.round().toString())}';
  }

  static String _resolveDestino(Map<String, dynamic> data) {
    final destino = data['destino'];
    if (destino is Map<String, dynamic>) {
      final direccion = destino['direccion']?.toString().trim();
      if (direccion?.isNotEmpty == true) return direccion!;

      final address = destino['address']?.toString().trim();
      if (address?.isNotEmpty == true) return address!;

      final direccionDestino = destino['direccion_destino']?.toString().trim();
      if (direccionDestino?.isNotEmpty == true) return direccionDestino!;

      final title = destino['title']?.toString().trim();
      if (title?.isNotEmpty == true) return title!;
    }

    final direccionSeleccionada = data['direccion_seleccionada']
        ?.toString()
        .trim();
    return (direccionSeleccionada?.isNotEmpty == true)
        ? direccionSeleccionada!
        : 'No disponible';
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResumenConductorViewModel(solicitudId: solicitudId),
      child: Consumer<ResumenConductorViewModel>(
        builder: (context, vm, _) {
          if (vm.cargando) {
            return const Scaffold(
              backgroundColor: AppColores.background,
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final media = MediaQuery.of(context);
          final size = media.size;
          final screenWidth = size.width;
          final screenHeight = size.height;
          final isTablet = screenWidth >= 600;
          final isDesktop = screenWidth >= 1024;
          final scale = (screenWidth / 390).clamp(0.92, isDesktop ? 1.45 : 1.2);
          final horizontalPadding = isDesktop ? 56.0 : (isTablet ? 36.0 : 20.0);
          final buttonHeight = isDesktop ? 62.0 : (isTablet ? 56.0 : 52.0);
            final buttonBottomInset =
              Theme.of(context).platform == TargetPlatform.android ? 34.0 : 24.0;
          final contentMaxWidth = isDesktop ? 760.0 : 620.0;
          final imageHeight = (screenHeight * (isDesktop ? 0.24 : 0.2)).clamp(
            150.0,
            isDesktop ? 280.0 : 220.0,
          );
          final titleFont = isDesktop ? 21.0 : (isTablet ? 18.0 : 16.0);
          final contentFont = isDesktop ? 20.0 : (isTablet ? 17.0 : 15.0);

          final TextStyle titleStyle = TextStyle(
            fontSize: titleFont * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );
          final TextStyle contentStyle = TextStyle(
            fontSize: contentFont * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );

          final data = vm.solicitudData ?? <String, dynamic>{};
          final direccionSeleccionada = _resolveDestino(data);
          final metodoPago = data['metodo_pago'];
          final horaFin = data['fecha de terminacion'] is Timestamp
              ? data['fecha de terminacion'] as Timestamp
              : null;
          final valorServicio = data['valor'] ?? 0;

          return Scaffold(
            backgroundColor: AppColores.background,
            body: SafeArea(
              bottom: false,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColores.surface, AppColores.background],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16 * scale,
                        horizontalPadding,
                        8 * scale,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 4 * scale),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppColores.success,
                                size: isDesktop ? 38 : 30,
                              ),
                              SizedBox(width: 8 * scale),
                              Flexible(
                                child: Text(
                                  'Viaje terminado',
                                  style: TextStyle(
                                    fontSize: (isDesktop ? 30 : 25) * scale,
                                    fontWeight: FontWeight.w700,
                                    color: AppColores.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10 * scale),
                          Flexible(
                            flex: 2,
                            child: Center(
                              child: Image.asset(
                                'assets/img/taxi.png',
                                height: imageHeight,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          SizedBox(height: 10 * scale),
                          Card(
                            color: AppColores.textPrimary,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 16 * scale,
                                horizontal: 14 * scale,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.local_taxi,
                                          color: AppColores.buttonPrimary,
                                          size: isDesktop ? 30 : 24,
                                        ),
                                        SizedBox(width: 8 * scale),
                                        Flexible(
                                          child: Text(
                                            'Valor del servicio',
                                            style: TextStyle(
                                              color: AppColores.textWhite,
                                              fontSize: 15.5 * scale,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _formatCurrency(valorServicio),
                                    style: TextStyle(
                                      color: AppColores.buttonPrimary,
                                      fontSize: (isDesktop ? 24 : 20) * scale,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 10 * scale),
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(14 * scale),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColores.primary,
                                      child: Icon(
                                        Icons.person,
                                        color: AppColores.textPrimary,
                                      ),
                                    ),
                                    title: Text(
                                      vm.nombreCliente,
                                      style: contentStyle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Divider(height: 8),
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColores.secondary
                                          .withValues(alpha: 0.12),
                                      child: const Icon(
                                        Icons.location_on,
                                        color: AppColores.secondary,
                                      ),
                                    ),
                                    title: Text('Destino', style: titleStyle),
                                    subtitle: Text(
                                      direccionSeleccionada,
                                      style: contentStyle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Divider(height: 8),
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColores.grey100,
                                      child: Icon(
                                        Icons.payment,
                                        color: AppColores.warning,
                                      ),
                                    ),
                                    title: Text(
                                      'Metodo de pago',
                                      style: titleStyle,
                                    ),
                                    subtitle: Text(
                                      _formatMetodo(metodoPago),
                                      style: contentStyle,
                                    ),
                                  ),
                                  const Divider(height: 8),
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColores.grey100,
                                      child: Icon(
                                        Icons.schedule,
                                        color: AppColores.warning,
                                      ),
                                    ),
                                    title: Text(
                                      'Hora de finalizacion',
                                      style: titleStyle,
                                    ),
                                    subtitle: Text(
                                      horaFin != null
                                          ? vm.formatoHoraBogota(horaFin)
                                          : 'No disponible',
                                      style: contentStyle,
                                    ),
                                  ),
                                ],
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
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: EdgeInsets.fromLTRB(
                horizontalPadding,
                8,
                horizontalPadding,
                buttonBottomInset,
              ),
              child: CustomButton(
                text: 'Volver a Inicio',
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider(
                        create: (_) => InicioConductorViewmodel(),
                        child: const InicioConductor(),
                      ),
                    ),
                    (route) => false,
                  );
                },
                width: double.infinity,
                height: buttonHeight,
                color: AppColores.buttonPrimary,
              ),
            ),
          );
        },
      ),
    );
  }

  static String _formatMetodo(dynamic metodo) {
    if (metodo == null) return '—';
    final s = metodo.toString().toLowerCase();
    if (s.isEmpty) return '—';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }
}
