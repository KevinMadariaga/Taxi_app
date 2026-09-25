import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/utils/moneda_format.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Propone cambiar el valor de la oferta cuando la búsqueda lleva rato sin
/// conductor. Devuelve el nuevo valor, o `null` si el cliente eligió seguir
/// buscando con el actual.
///
/// No conoce el ViewModel a propósito: recibe el valor y el validador, así
/// que se puede montar en un widget test sin Firestore. Quien lo abre es el
/// que escribe en la solicitud.
///
/// No se descarta tocando afuera ni con el back de Android
/// (`barrierDismissible: false` + `PopScope`): el silencio es justamente lo
/// que cancela la búsqueda, así que tiene que ser una decisión explícita.
Future<double?> mostrarCambiarOfertaDialog(
  BuildContext context, {
  required double valorActual,
  required String? Function(String digits) validar,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _CambiarOfertaDialog(valorActual: valorActual, validar: validar),
  );
}

class _CambiarOfertaDialog extends StatefulWidget {
  const _CambiarOfertaDialog({
    required this.valorActual,
    required this.validar,
  });

  final double valorActual;
  final String? Function(String digits) validar;

  @override
  State<_CambiarOfertaDialog> createState() => _CambiarOfertaDialogState();
}

class _CambiarOfertaDialogState extends State<_CambiarOfertaDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final inicial = formatCurrency(widget.valorActual);
    _controller = TextEditingController(text: inicial);
    // Texto preseleccionado: escribir reemplaza el valor de una vez, sin
    // tener que borrarlo dígito a dígito (mismo criterio que
    // `EditarOfertaBusquedaView`).
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: inicial.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reformatea el separador de miles mientras se escribe. Escribir en el
  /// controller desde acá no re-dispara `onChanged` (solo lo hace el input
  /// del usuario), así que no hace falta guard de reentrada.
  void _onChanged(String value) {
    final formateado = formatCurrencyFromRaw(value);
    _controller.value = TextEditingValue(
      text: formateado,
      selection: TextSelection.collapsed(offset: formateado.length),
    );
    if (_error != null) setState(() => _error = null);
  }

  void _confirmar() {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    final error = widget.validar(digits);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, double.parse(digits));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PopScope(
      // El back de Android tampoco descarta la pregunta: cerrarla sin
      // contestar equivale al silencio que cancela la búsqueda.
      canPop: false,
      child: AlertDialog(
        // Con el teclado abierto en pantallas chicas el alto disponible se
        // achica y el contenido no entra: `AlertDialog` no scrollea solo.
        scrollable: true,
        title: const Text('¿Sigues buscando?', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Aún no encontramos un conductor.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6.h),
            // Separado del de arriba: la frase corta dice el estado, esta
            // dice qué puede hacer. Juntas en un párrafo de tres líneas
            // centradas no se leían.
            Text(
              'Puedes cambiar el valor de tu oferta para conseguir uno más '
              'rápido, o continuar buscando con el valor actual.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: palette.textSecondary),
            ),
            SizedBox(height: 18.h),
            Text(
              'Valor del servicio',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.sp),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: _controller,
              // Sin `autofocus`: el teclado no se abre solo dentro de un
              // diálogo (mismo criterio que `dialogo_dias_membresia.dart`).
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: _onChanged,
              onSubmitted: (_) => _confirmar(),
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20.sp),
              decoration: InputDecoration(
                // El rótulo va arriba como texto centrado: un `labelText`
                // flotante se ancla a la izquierda y rompía el centrado.
                prefix: const Text('\$ '),
                // Espejo transparente del prefijo: mismos glifos, mismo
                // ancho, así el número queda centrado de verdad en la caja y
                // no corrido a la derecha por el '$'.
                suffix: const Text(
                  '\$ ',
                  style: TextStyle(color: Colors.transparent),
                ),
                hintText: 'Ej: 11.000',
                errorText: _error,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actionsPadding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
        actions: [
          // Uno encima del otro, a lo ancho: en media caja del diálogo
          // "Continuar buscando" no entra y `CustomButton` la corta con
          // ellipsis (`maxLines: 1`), así que el cliente no alcanzaba a leer
          // qué estaba eligiendo. Apilados, cada etiqueta entra completa y
          // el área tocable es más grande. La acción propuesta va arriba.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomButton(
                text: 'Cambiar oferta',
                color: AppColores.buttonPrimary,
                height: 48.h,
                fontSize: 15.sp,
                onPressed: _confirmar,
              ),
              SizedBox(height: 10.h),
              CustomButton(
                text: 'Continuar buscando',
                color: palette.surface,
                textColor: AppColores.primary,
                borderColor: AppColores.primary,
                height: 48.h,
                fontSize: 15.sp,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
