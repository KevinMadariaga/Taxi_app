import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/resumen_cliente_viewmodel.dart';

class ResumenClienteView extends StatefulWidget {
  final String solicitudId;
  const ResumenClienteView({super.key, required this.solicitudId});

  @override
  State<ResumenClienteView> createState() => _ResumenClienteViewState();
}

class _ResumenClienteViewState extends State<ResumenClienteView> {
  bool _accionEnProgreso = false;

  // Utilidades para formato
  String _thousands(String s) {
    final r = s.split('').reversed.toList();
    final out = <String>[];
    for (int i = 0; i < r.length; i++) {
      if (i != 0 && i % 3 == 0) out.add('.');
      out.add(r[i]);
    }
    return out.reversed.join();
  }

  String _formatCurrency(dynamic v) {
    final num n = v is num ? v : num.tryParse(v.toString()) ?? 0;
    return "\$${_thousands(n.round().toString())}";
  }

  String _formatMetodo(dynamic metodo) {
    if (metodo == null) return '—';
    final s = metodo.toString().toLowerCase();
    if (s.isEmpty) return '—';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  // Construye el card de valor del servicio
  Widget _buildValorCard(double scale, dynamic valorServicio) {
    return Card(
      color: AppColores.textPrimary,
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
                  color: AppColores.buttonPrimary,
                ),
                SizedBox(width: 8 * scale),
                Text(
                  'Valor del servicio',
                  style: TextStyle(
                    color: AppColores.textWhite,
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Text(
              _formatCurrency(valorServicio),
              style: TextStyle(
                color: AppColores.buttonPrimary,
                fontSize: 20 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Construye el card principal con resumen del viaje
  Widget _buildResumenCard(double scale, TextStyle titleStyle, TextStyle contentStyle, ResumenClienteViewModel vm, String destinoTexto, dynamic metodoPago) {
    return Card(
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
                  color: AppColores.textPrimary,
                ),
              ),
              title: Text(
                vm.nombreConductor,
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
                destinoTexto,
                style: contentStyle,
                maxLines: 1,
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
                'Método de pago',
                style: titleStyle,
              ),
              subtitle: Text(
                _formatMetodo(metodoPago),
                style: contentStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Construye el botón principal (continuar o volver)
  Widget _buildMainButton(bool calificacionEnviada, double padding, double buttonHeight, double scale, ResumenClienteViewModel vm) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: CustomButton(
        text: calificacionEnviada ? 'Volver a Inicio' : 'Continuar',
        onPressed: _accionEnProgreso
            ? null
            : () {
                setState(() {
                  _accionEnProgreso = true;
                });
                if (calificacionEnviada) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const InicioClienteView(),
                    ),
                    (route) => false,
                  );
                  setState(() {
                    _accionEnProgreso = false;
                  });
                } else {
                  _mostrarDialogoCalificacion(
                    context,
                    vm,
                    scale,
                    padding,
                  ).whenComplete(() {
                    if (mounted) {
                      setState(() {
                        _accionEnProgreso = false;
                      });
                    }
                  });
                }
              },
        width: double.infinity,
        height: buttonHeight,
        color: AppColores.buttonPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResumenClienteViewModel(solicitudId: widget.solicitudId),
      child: Consumer<ResumenClienteViewModel>(
        builder: (context, vm, _) {
          final size = MediaQuery.of(context).size;
          final screenWidth = size.width;
          final screenHeight = size.height;
          final scale = (screenWidth / 375).clamp(0.9, 1.2);

          final double padding = 24 * scale;
          final double imageHeight = (screenHeight * 0.22).clamp(140, 220);
          final double buttonHeight = 52 * scale;
          final TextStyle titleStyle = TextStyle(
            fontSize: 16 * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );
          final TextStyle contentStyle = TextStyle(
            fontSize: 15 * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );

          if (vm.cargando) {
            return const Scaffold(
              backgroundColor: AppColores.background,
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Extrae datos de la solicitud
          final data = vm.solicitudData ?? <String, dynamic>{};
          final destinoRaw = data['destino'];
          String destinoTexto = 'No disponible';
          if (destinoRaw is Map<String, dynamic>) {
            final d = destinoRaw;
            if (d['title']?.toString().trim().isNotEmpty == true) {
              destinoTexto = d['title'].toString();
            } else {
              destinoTexto =
                  data['direccion_seleccionada']?.toString() ??
                  d['direccion']?.toString() ??
                  'No disponible';
            }
          } else {
            destinoTexto =
                data['direccion_seleccionada']?.toString() ?? 'No disponible';
          }
          final metodoPago = data['metodo_pago'];
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
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: padding * 0.5,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: padding * 0.25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColores.success,
                            size: 30,
                          ),
                          SizedBox(width: 5 * scale),
                          Text(
                            'Viaje completado',
                            style: TextStyle(
                              fontSize: 25 * scale,
                              fontWeight: FontWeight.w700,
                              color: AppColores.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: padding * 0.25),
                      Image.asset(
                        'assets/img/taxi.png',
                        height: imageHeight,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: padding * 0.2),
                      _buildValorCard(scale, valorServicio),
                      SizedBox(height: padding * 0.4),
                      _buildResumenCard(scale, titleStyle, contentStyle, vm, destinoTexto, metodoPago),
                      SizedBox(height: (40 * scale) + 40),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: _buildMainButton(vm.calificacionEnviada, padding, buttonHeight, scale, vm),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerFloat,
          );
        },
      ),
    );
  }

  // ...existing code...
  }

  Future<void> _mostrarDialogoCalificacion(
    BuildContext context,
    ResumenClienteViewModel vm,
    double scale,
    double padding,
  ) {
    final TextEditingController comentarioController = TextEditingController();

    return showDialog(
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
                          color: AppColores.textPrimary,
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
                              padding: EdgeInsets.symmetric(
                                horizontal: 4 * scale,
                              ),
                              child: Icon(
                                index < vm.calificacion
                                    ? Icons.star
                                    : Icons.star_border,
                                color: AppColores.buttonPrimary,
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
                            color: AppColores.buttonPrimary,
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
                              color: AppColores.grey400,
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
                                backgroundColor: AppColores.grey200,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20 * scale,
                                  vertical: 12 * scale,
                                ),
                              ),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: AppColores.textPrimary,
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
                                        builder: (_) =>
                                            const InicioClienteView(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20 * scale,
                                  vertical: 12 * scale,
                                ),
                              ),
                              child: Text(
                                'Aceptar',
                                style: TextStyle(
                                  color: AppColores.textPrimary,
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
// ...existing code...
