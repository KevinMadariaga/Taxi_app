import 'package:flutter/material.dart';

import '../../../dominio/modelos/crear_solicitud_resultado.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../viewmodels/confirmar_solicitud_viewmodel.dart';
import 'programar_viaje_sheet.dart';
import 'tipo_vehiculo_sheet.dart';

/// Botón "Buscar conductor" a todo el ancho. Pago y nota viven en
/// `OpcionesViajeRow`, justo arriba. [onSolicitudCreada] navega a la
/// pantalla de búsqueda — la vista es quien decide a dónde ir, esta fila
/// solo dispara la creación.
///
/// El tipo de vehículo ya no tiene su propio selector fijo en la pantalla:
/// "Buscar conductor" abre primero la modal de vehículo
/// (`mostrarTipoVehiculoSheet`) y solo sigue con la creación si el usuario
/// confirmó ahí — si cierra la modal sin confirmar, el tap completo se
/// cancela sin tocar Firestore.
class ConfirmarSolicitudSubmitBar extends StatelessWidget {
  const ConfirmarSolicitudSubmitBar({
    super.key,
    required this.onSolicitudCreada,
  });

  final ValueChanged<String> onSolicitudCreada;

  /// Alto compartido con [PedirMasTardeBoton], que va al lado.
  static double altura(BuildContext context) =>
      ResponsiveHelper.hp(context, 6.5).clamp(50.0, 62.0);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final buttonHeight = altura(context);

    return SizedBox(
      width: double.infinity,
      height: buttonHeight,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColores.buttonPrimary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColores.buttonPrimary.withValues(
            alpha: 0.6,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: vm.isSubmitting
            ? null
            : () async {
                final confirmado = await mostrarTipoVehiculoSheet(context, vm);
                if (confirmado != true || !context.mounted) return;

                final messenger = ScaffoldMessenger.of(context);
                final resultado = await vm.crearSolicitud();
                if (!context.mounted) return;

                switch (resultado) {
                  case SolicitudCreada(:final solicitudId):
                    onSolicitudCreada(solicitudId);
                  case SolicitudActivaExistente(:final solicitudId):
                    // Antes este caso era indistinguible del anterior:
                    // se descartaban en silencio el destino, precio,
                    // vehículo, método de pago y comentario recién
                    // elegidos, y se navegaba a la espera de un viaje
                    // distinto sin ninguna explicación.
                    final continuar = await _confirmarViajeEnCurso(context);
                    if (continuar == true) {
                      onSolicitudCreada(solicitudId);
                    }
                  case CrearSolicitudFallo(:final motivo):
                    messenger.showSnackBar(SnackBar(content: Text(motivo)));
                }
              },
        child: vm.isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.4,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Buscar conductor',
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 16),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Explica que ya hay un viaje en curso y deja elegir entre ir a verlo o
/// quedarse para cancelarlo primero.
Future<bool?> _confirmarViajeEnCurso(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ya tienes un viaje en curso'),
      content: const Text(
        'No se creó una solicitud nueva. Puedes ir a ver el viaje que ya '
        'tienes activo, o quedarte aquí y cancelarlo primero.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Quedarme aquí'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ver viaje activo'),
        ),
      ],
    ),
  );
}

/// Sin uso por ahora: el dueño pidió retirar "Pedir para más tarde" de la
/// pantalla (2026-11-10). El backend de viajes programados sigue activo.
///
/// "Pedir para más tarde": mismo paso de vehículo que buscar ahora y, en vez de
/// salir a buscar, elige fecha y deja el viaje programado. Va como acción
/// secundaria al lado de "Buscar conductor", con su mismo alto.
class PedirMasTardeBoton extends StatelessWidget {
  const PedirMasTardeBoton({
    super.key,
    required this.onProgramado,
    this.soloIcono = false,
  });

  final ValueChanged<DateTime> onProgramado;

  /// Pantallas angostas: solo el reloj (con tooltip y etiqueta accesible).
  final bool soloIcono;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConfirmarSolicitudViewModel>();
    final palette = context.palette;
    final alto = ConfirmarSolicitudSubmitBar.altura(context);
    final estilo = OutlinedButton.styleFrom(
      foregroundColor: palette.textPrimary,
      iconColor: AppColores.primary,
      side: BorderSide(color: palette.borderSubtle, width: 1.5),
      minimumSize: Size(alto, alto),
      padding: EdgeInsets.symmetric(horizontal: soloIcono ? 0 : 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    final onPressed = vm.isSubmitting
        ? null
        : () async {
            final confirmado = await mostrarTipoVehiculoSheet(context, vm);
            if (confirmado != true || !context.mounted) return;
            final cuando = await mostrarProgramarViajeSheet(context);
            if (cuando == null || !context.mounted) return;

            final messenger = ScaffoldMessenger.of(context);
            final resultado = await vm.crearSolicitud(programadaPara: cuando);
            if (!context.mounted) return;
            switch (resultado) {
              case SolicitudCreada():
                onProgramado(cuando);
              case SolicitudActivaExistente():
                // No ocurre al programar: el caso de uso no la consulta.
                break;
              case CrearSolicitudFallo(:final motivo):
                messenger.showSnackBar(SnackBar(content: Text(motivo)));
            }
          };
    const icono = Icon(Icons.schedule_rounded, size: 22);
    return Tooltip(
      message: 'Pedir para más tarde',
      child: SizedBox(
        height: alto,
        child: soloIcono
            ? OutlinedButton(
                style: estilo,
                onPressed: onPressed,
                child: Semantics(label: 'Pedir para más tarde', child: icono),
              )
            : OutlinedButton.icon(
                style: estilo,
                onPressed: onPressed,
                icon: icono,
                label: const Text(
                  'Más tarde',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
    );
  }
}
