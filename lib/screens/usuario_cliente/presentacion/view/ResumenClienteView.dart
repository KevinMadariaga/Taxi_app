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
    return '\$${_thousands(n.round().toString())}';
  }

  String _formatMetodo(dynamic metodo) {
    if (metodo == null) return '-';
    final s = metodo.toString().trim().toLowerCase();
    if (s.isEmpty) return '-';
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  String _resolveDestino(Map<String, dynamic> data) {
    final destinoRaw = data['destino'];
    if (destinoRaw is Map<String, dynamic>) {
      final title = destinoRaw['title']?.toString().trim();
      if (title?.isNotEmpty == true) return title!;

      final direccion = destinoRaw['direccion']?.toString().trim();
      if (direccion?.isNotEmpty == true) return direccion!;

      final address = destinoRaw['address']?.toString().trim();
      if (address?.isNotEmpty == true) return address!;
    }

    final direccionSeleccionada = data['direccion_seleccionada']
        ?.toString()
        .trim();
    return (direccionSeleccionada?.isNotEmpty == true)
        ? direccionSeleccionada!
        : 'No disponible';
  }

  Widget _buildValorCard({
    required double scale,
    required bool isDesktop,
    required dynamic valorServicio,
  }) {
    return Card(
      color: AppColores.textPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: 16 * scale,
          horizontal: 14 * scale,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.local_taxi,
                    color: AppColores.buttonPrimary,
                    size: isDesktop ? 32 : 26,
                  ),
                  SizedBox(width: 10 * scale),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenCard({
    required double scale,
    required TextStyle titleStyle,
    required TextStyle contentStyle,
    required ResumenClienteViewModel vm,
    required String destinoTexto,
    required dynamic metodoPago,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(14 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColores.primary,
                child: Icon(Icons.person, color: AppColores.textPrimary),
              ),
              title: Text(
                vm.nombreConductor,
                style: contentStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 8),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColores.secondary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.location_on,
                  color: AppColores.secondary,
                ),
              ),
              title: Text('Destino', style: titleStyle),
              subtitle: Text(
                destinoTexto,
                style: contentStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColores.grey100,
                child: Icon(Icons.payment, color: AppColores.warning),
              ),
              title: Text('Metodo de pago', style: titleStyle),
              subtitle: Text(_formatMetodo(metodoPago), style: contentStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainButton({
    required bool calificacionEnviada,
    required double buttonHeight,
    required ResumenClienteViewModel vm,
    required double scale,
  }) {
    return CustomButton(
      text: calificacionEnviada ? 'Volver a Inicio' : 'Continuar',
      onPressed: _accionEnProgreso
          ? null
          : () {
              setState(() {
                _accionEnProgreso = true;
              });

              if (calificacionEnviada) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const InicioClienteView()),
                  (route) => false,
                );
                if (mounted) {
                  setState(() {
                    _accionEnProgreso = false;
                  });
                }
                return;
              }

              _mostrarDialogoCalificacion(context, vm, scale).whenComplete(() {
                if (mounted) {
                  setState(() {
                    _accionEnProgreso = false;
                  });
                }
              });
            },
      width: double.infinity,
      height: buttonHeight,
      color: AppColores.buttonPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ResumenClienteViewModel(solicitudId: widget.solicitudId),
      child: Consumer<ResumenClienteViewModel>(
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
          final contentMaxWidth = isDesktop ? 760.0 : 620.0;
          final imageHeight = (screenHeight * (isDesktop ? 0.24 : 0.2)).clamp(
            150.0,
            isDesktop ? 280.0 : 220.0,
          );

          final titleStyle = TextStyle(
            fontSize: (isDesktop ? 21 : (isTablet ? 18 : 16)) * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );
          final contentStyle = TextStyle(
            fontSize: (isDesktop ? 20 : (isTablet ? 17 : 15)) * scale,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          );

          final data = vm.solicitudData ?? <String, dynamic>{};
          final destinoTexto = _resolveDestino(data);
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
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppColores.success,
                                  size: isDesktop ? 42 : 32,
                                ),
                                SizedBox(height: 8 * scale),
                                Text(
                                  'Viaje completado',
                                  style: TextStyle(
                                    fontSize: (isDesktop ? 34 : 26) * scale,
                                    fontWeight: FontWeight.w700,
                                    color: AppColores.textPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
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
                          _buildValorCard(
                            scale: scale,
                            isDesktop: isDesktop,
                            valorServicio: valorServicio,
                          ),
                          SizedBox(height: 10 * scale),
                          _buildResumenCard(
                            scale: scale,
                            titleStyle: titleStyle,
                            contentStyle: contentStyle,
                            vm: vm,
                            destinoTexto: destinoTexto,
                            metodoPago: metodoPago,
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
                24,
              ),
              child: _buildMainButton(
                calificacionEnviada: vm.calificacionEnviada,
                buttonHeight: buttonHeight,
                vm: vm,
                scale: scale,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _mostrarDialogoCalificacion(
    BuildContext context,
    ResumenClienteViewModel vm,
    double scale,
  ) {
    final comentarioController = TextEditingController();
    bool accionDialogoEnProgreso = false;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(22 * scale),
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
                      SizedBox(height: 18 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
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
                                size: 38 * scale,
                              ),
                            ),
                          );
                        }),
                      ),
                      SizedBox(height: 12 * scale),
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
                        SizedBox(height: 14 * scale),
                        TextField(
                          controller: comentarioController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Cuentanos que paso...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintStyle: TextStyle(
                              fontSize: 14 * scale,
                              color: AppColores.grey400,
                            ),
                          ),
                          onChanged: vm.setComentarioCalificacion,
                        ),
                      ],
                      SizedBox(height: 18 * scale),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.grey200,
                                padding: EdgeInsets.symmetric(
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
                          Expanded(
                            child: ElevatedButton(
                              onPressed: accionDialogoEnProgreso
                                  ? null
                                  : () async {
                                      if (vm.calificacion <= 0) return;

                                      setDialogState(() {
                                        accionDialogoEnProgreso = true;
                                      });

                                      await vm.enviarCalificacion();

                                      if (!dialogContext.mounted) return;
                                      Navigator.pop(dialogContext);

                                      if (!mounted) return;
                                      if (vm.calificacionEnviada) {
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const InicioClienteView(),
                                          ),
                                          (route) => false,
                                        );
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              vm.mensajeCalificacion ??
                                                  'No se pudo enviar la calificacion',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                padding: EdgeInsets.symmetric(
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
}
