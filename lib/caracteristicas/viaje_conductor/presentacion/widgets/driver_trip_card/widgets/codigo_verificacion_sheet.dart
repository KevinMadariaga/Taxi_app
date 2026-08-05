import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Bottom sheet donde el conductor ingresa el código de 4 dígitos que el
/// cliente le dijo de viva voz — reemplaza la transición directa
/// (enCamino→enRuta) que antes ocurría con un simple tap en "Comenzar
/// ruta".
///
/// [onValidar] es la llamada al viewmodel (`validarCodigoRecogida`); este
/// widget solo maneja el input y el feedback de error, sin tocar Firestore
/// directamente.
class CodigoVerificacionSheet extends StatefulWidget {
  const CodigoVerificacionSheet({
    super.key,
    required this.onValidar,
    required this.isValidating,
  });

  final Future<ResultadoValidacionCodigo> Function(String codigo) onValidar;
  final bool isValidating;

  static Future<bool?> mostrar(
    BuildContext context, {
    required Future<ResultadoValidacionCodigo> Function(String codigo)
    onValidar,
    required bool Function() isValidating,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CodigoVerificacionSheet(
        onValidar: onValidar,
        isValidating: isValidating(),
      ),
    );
  }

  @override
  State<CodigoVerificacionSheet> createState() =>
      _CodigoVerificacionSheetState();
}

class _CodigoVerificacionSheetState extends State<CodigoVerificacionSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _validando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final codigo = _controller.text.trim();
    if (codigo.length != 4) {
      setState(() => _error = 'Ingresa los 4 dígitos.');
      return;
    }

    setState(() {
      _validando = true;
      _error = null;
    });

    final resultado = await widget.onValidar(codigo);

    if (!mounted) return;
    setState(() => _validando = false);

    switch (resultado) {
      case ResultadoValidacionCodigo.correcto:
        Navigator.of(context).pop(true);
        break;
      case ResultadoValidacionCodigo.incorrecto:
        setState(() => _error = 'Código incorrecto, verifica con el cliente.');
        break;
      case ResultadoValidacionCodigo.noGenerado:
        setState(
          () => _error = 'Todavía no se generó un código para este viaje.',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: const BoxDecoration(
          color: AppColores.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColores.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Código de verificación',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pídele al cliente el código de 4 dígitos que ve en su pantalla.',
              style: TextStyle(fontSize: 13, color: AppColores.textSecondary),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 12,
                color: AppColores.textPrimary,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '0000',
                filled: true,
                fillColor: AppColores.grey100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColores.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            CustomButton(
              text: 'Validar código',
              isLoading: _validando,
              onPressed: _validando ? null : _submit,
              width: double.infinity,
              height: 50,
            ),
          ],
        ),
      ),
    );
  }
}
