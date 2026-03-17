import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';

import '../controllers/resumen_viaje_controller.dart';
import '../models/resumen_viaje_model.dart';
import '../widgets/calificacion_section.dart';
import '../widgets/resumen_header.dart';
import '../widgets/resumen_info_item.dart';

class ResumenViajeView extends StatelessWidget {
  const ResumenViajeView({
    super.key,
    required this.tipoUsuario,
    required this.solicitudId,
  });

  final TipoUsuarioResumen tipoUsuario;
  final String solicitudId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ResumenViajeController>(
      create: (_) => ResumenViajeController(
        tipoUsuario: tipoUsuario,
        solicitudId: solicitudId,
      ),
      child: const _ResumenViajeBody(),
    );
  }
}

class _ResumenViajeBody extends StatelessWidget {
  const _ResumenViajeBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ResumenViajeController>();

    return StreamBuilder<ResumenViajeModel>(
      stream: controller.resumenStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColores.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColores.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColores.buttonCancel,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No pudimos cargar el resumen del viaje.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColores.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColores.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final resumen = snapshot.data;
        if (resumen == null) {
          return const Scaffold(
            backgroundColor: AppColores.background,
            body: Center(
              child: Text(
                'No hay informacion disponible para este viaje.',
                style: TextStyle(
                  color: AppColores.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        controller.sincronizarFormulario(resumen);
        return Consumer<ResumenViajeController>(
          builder: (context, vm, _) {
            final isCliente = vm.tipoUsuario == TipoUsuarioResumen.cliente;
            final horizontalPadding = MediaQuery.of(context).size.width >= 900
                ? 44.0
                : 20.0;

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
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          18,
                          horizontalPadding,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const ResumenHeader(),
                            const SizedBox(height: 14),
                            _SummaryCard(resumen: resumen, isCliente: isCliente),
                            if (isCliente) ...[
                              const SizedBox(height: 10),
                              CalificacionSection(
                                calificacion: vm.calificacionSeleccionada,
                                onCalificacionChanged: vm.setCalificacion,
                                requiereComentario: vm.requiereComentario,
                                comentarioInicial: vm.comentarioCalificacion,
                                onComentarioChanged: vm.setComentario,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                minimum: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 24),
                child: CustomButton(
                  text: isCliente ? 'Continuar' : 'Volver al inicio',
                  onPressed: vm.guardando
                      ? null
                      : () async {
                          await _onActionPressed(context, vm);
                        },
                  width: double.infinity,
                  height: 52,
                  color: AppColores.buttonPrimary,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _onActionPressed(
    BuildContext context,
    ResumenViajeController vm,
  ) async {
    final isCliente = vm.tipoUsuario == TipoUsuarioResumen.cliente;

    if (isCliente) {
      final error = await vm.guardarCalificacionCliente();
      if (!context.mounted) return;

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InicioClienteView()),
        (route) => false,
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const InicioConductor()),
      (route) => false,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.resumen, required this.isCliente});

  final ResumenViajeModel resumen;
  final bool isCliente;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ResumenInfoItem(
              icon: Icons.person,
              label: isCliente ? 'Conductor' : 'Cliente',
              value: isCliente ? resumen.conductorNombre : resumen.clienteNombre,
            ),
            const Divider(height: 14),
            ResumenInfoItem(
              icon: Icons.location_on,
              label: 'Destino',
              value: resumen.destinoDireccion,
            ),
            const Divider(height: 14),
            ResumenInfoItem(
              icon: Icons.local_taxi,
              label: 'Valor del servicio',
              value: _currency(resumen.valorServicio),
            ),
            const Divider(height: 14),
            ResumenInfoItem(
              icon: Icons.event,
              label: 'Fecha del viaje',
              value: _fecha(resumen.fechaViaje),
            ),
          ],
        ),
      ),
    );
  }

  String _currency(double value) {
    final formatter = NumberFormat.currency(
      locale: 'es_CO',
      symbol: r'$',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  String _fecha(DateTime? value) {
    if (value == null) return 'No disponible';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    var hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = hour >= 12 ? 'PM' : 'AM';

    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }

    final hourText = hour.toString().padLeft(2, '0');
    return '$day/$month/$year $hourText:$minute $suffix';
  }
}
