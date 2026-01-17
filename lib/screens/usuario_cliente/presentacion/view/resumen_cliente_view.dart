import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/resumen_cliente_viewmodel.dart';


class ResumenClienteView extends StatelessWidget {
  final String solicitudId;
  const ResumenClienteView({super.key, required this.solicitudId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResumenClienteViewModel(solicitudId: solicitudId),
      child: Consumer<ResumenClienteViewModel>(
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
            fontSize: 15 * scale,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          );

          if (vm.cargando) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final data = vm.solicitudData ?? <String, dynamic>{};
          final destinoRaw = data['destino'];
          String destinoTexto = data['direccion_seleccionada'] ?? 'No disponible';
          if (destinoRaw is Map<String, dynamic>) {
            destinoTexto = destinoRaw['title']?.toString() ?? destinoTexto;
          }
          final metodoPago = data['metodo_pago'];
          final horaFin = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
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
                      SizedBox(height: padding * 0.5),
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
                            'Viaje completado',
                            style: TextStyle(
                              fontSize: 30 * scale,
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
                      SizedBox(height: padding * 0.5),
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
                      SizedBox(height: padding * 0.5),
                      // Card principal con resumen
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(15 * scale),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColores.primary,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.black,
                                  ),
                                ),
                                title: Text(
                                  vm.nombreConductor,
                                  style: contentStyle,
                                ),
                              ),
                              const Divider(height: 8),
                              ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColores.secondary,
                                  child: Icon(
                                    Icons.location_on,
                                    color: Colors.blue,
                                  ),
                                ),
                                title: Text('Destino', style: titleStyle),
                                subtitle: Text(
                                  destinoTexto,
                                  style: contentStyle,
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
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 60 * scale),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: !vm.calificacionEnviada
                ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: CustomButton(
                      text: 'Continuar',
                      onPressed: () {
                        _mostrarDialogoCalificacion(context, vm, scale, padding);
                      },
                      width: double.infinity,
                      height: buttonHeight,
                      color: const Color(0xFFFFD600),
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: CustomButton(
                      text: 'Volver a Inicio',
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      width: double.infinity,
                      height: buttonHeight,
                      color: const Color(0xFFFFD600),
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

  static void _mostrarDialogoCalificacion(
    BuildContext context,
    ResumenClienteViewModel vm,
    double scale,
    double padding,
  ) {
    final TextEditingController comentarioController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(24 * scale),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Califica el servicio',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20 * scale,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 20 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                vm.setCalificacion((index + 1).toDouble());
                              });
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                              child: Icon(
                                index < vm.calificacion
                                    ? Icons.star
                                    : Icons.star_border,
                                color: const Color(0xFFFFD600),
                                size: 40 * scale,
                              ),
                            ),
                          );
                        }),
                      ),
                      SizedBox(height: 16 * scale),
                      if (vm.calificacion > 0)
                        Text(
                          '${vm.calificacion.toStringAsFixed(0)} de 5 estrellas',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14 * scale,
                            color: const Color(0xFFFFD600),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (vm.calificacion > 0 && vm.calificacion < 4) ...[
                        SizedBox(height: 16 * scale),
                        TextField(
                          controller: comentarioController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Cuéntanos qué pasó...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintStyle: TextStyle(
                              fontSize: 14 * scale,
                              color: Colors.grey,
                            ),
                          ),
                          onChanged: (value) {
                            vm.setComentarioCalificacion(value);
                          },
                        ),
                      ],
                      SizedBox(height: 20 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Flexible(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[300],
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20 * scale,
                                  vertical: 12 * scale,
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12 * scale),
                          Flexible(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (vm.calificacion > 0) {
                                  await vm.enviarCalificacion();
                                  if (context.mounted) {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (_) => const InicioClienteView(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD600),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20 * scale,
                                  vertical: 12 * scale,
                                ),
                              ),
                              child: Text(
                                'Aceptar',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
