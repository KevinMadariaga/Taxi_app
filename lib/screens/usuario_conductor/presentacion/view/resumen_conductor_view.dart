import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/resumen_conductor_viewmodel.dart';


class ResumenConductorView extends StatelessWidget {
  final String solicitudId;
  const ResumenConductorView({super.key, required this.solicitudId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResumenConductorViewModel(solicitudId: solicitudId),
      child: Consumer<ResumenConductorViewModel>(
        builder: (context, vm, _) {
          final screenWidth = MediaQuery.of(context).size.width;
          final scale = screenWidth / 375;

          final double padding = 24 * scale;
          final double imageHeight = 180 * scale;
          final double buttonHeight = 52 * scale;
          final TextStyle titleStyle = TextStyle(
            fontSize: 16 * scale,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          );
          final TextStyle contentStyle = TextStyle(
            fontSize: 16 * scale,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          );

          if (vm.cargando) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final data = vm.solicitudData ?? <String, dynamic>{};
          final destino = data['destino'];
          final direccionSeleccionada = destino is Map<String, dynamic> 
              ? (destino['title'] ?? 'No disponible') 
              : 'No disponible';
          final metodoPago = data['metodo_pago'];
          final horaFin = data['fecha de terminacion'] as Timestamp?;
          final valorServicio = data['valor'] ?? 0;

          String thousands(String s) {
            final r = s.split('').reversed.toList();
            final out = <String>[];
            for (int i = 0; i < r.length; i++) {
              if (i != 0 && i % 3 == 0) out.add('.');
              out.add(r[i]);
            }
            return out.reversed.join();
          }

          String formatCurrency(dynamic v) {
            final num n = v is num ? v : num.tryParse(v.toString()) ?? 0;
            return "\$${thousands(n.round().toString())}";
          }

          return Scaffold(
            backgroundColor: const Color(0xFFF7F7F7),
            body: SafeArea(
              bottom: false,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0xFFF7F7F7)],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: padding * 0.6,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: padding * 0.3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF00C853),
                            size: 30,
                          ),
                          SizedBox(width: 8 * scale),
                          Text(
                            'Viaje terminado',
                            style: TextStyle(
                              fontSize: 25 * scale,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.5),
                      Image.asset(
                        'assets/img/taxi.png',
                        height: imageHeight,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: padding * 0.1),
                      // Card del valor
                      Card(
                        color: const Color(0xFF101010),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 18 * scale,
                            horizontal: 16 * scale,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.local_taxi,
                                    color: Color(0xFFFFD600),
                                  ),
                                  SizedBox(width: 8 * scale),
                                  Text(
                                    'Valor del servicio',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14 * scale,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                formatCurrency(valorServicio),
                                style: TextStyle(
                                  color: const Color(0xFFFFD600),
                                  fontSize: 20 * scale,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: padding * 0.3),
                      // Card principal con resumen
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16 * scale),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFFFD600),
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.black,
                                  ),
                                ),
                                title: Text(
                                  vm.nombreCliente,
                                  style: contentStyle,
                                ),
                              ),
                              const Divider(height: 8),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColores.secondary.withOpacity(0.12),
                                  child: Icon(
                                    Icons.location_on,
                                    color: AppColores.secondary,
                                  ),
                                ),
                                title: Text('Destino', style: titleStyle),
                                  subtitle: Text(
                                    direccionSeleccionada ?? 'No disponible',
                                    style: contentStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ),
                              const Divider(height: 8),
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFFFF3E0),
                                  child: Icon(
                                    Icons.payment,
                                    color: Color(0xFFFF9800),
                                  ),
                                ),
                                title: Text(
                                  'Método de pago',
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
                                  backgroundColor: Color(0xFFFFF3E0),
                                  child: Icon(
                                    Icons.schedule,
                                    color: Color(0xFFFF9800),
                                  ),
                                ),
                                title: Text(
                                  'Hora de finalización',
                                  style: titleStyle,
                                ),
                                subtitle: Text(
                                  horaFin != null
                                      ? vm.formatoHoraBogota(horaFin)
                                      : 'No disponible',
                                  style: contentStyle,
                                ),
                              ),
                              const Divider(height: 5),
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE8F5E9),
                                  child: Icon(
                                    Icons.timer,
                                    color: Color(0xFF4CAF50),
                                  ),
                                ),
                                title: Text(
                                  'Duración del servicio',
                                  style: titleStyle,
                                ),
                                subtitle: Text(
                                  vm.formatoDuracion(vm.duracionMinutos),
                                  style: contentStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 90 * scale),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: CustomButton(
                text: 'Volver a Inicio',
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const HomeConductorMapView(),
                    ),
                    (route) => false,
                  );
                },
                width: double.infinity,
                height: buttonHeight,
                color: AppColores.buttonPrimary,
              ),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
