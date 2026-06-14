import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/sugerencias_service.dart';

const _kKeyCliente = 'sugerencia_viajes_cliente';
const _kKeyConductor = 'sugerencia_viajes_conductor';

/// Incrementa el contador de viajes y decide si corresponde mostrar el modal.
/// Muestra en el viaje 1 y luego cada 3 (3, 6, 9...).
Future<void> registrarViajeYMostrarSugerenciaModal(
  BuildContext context, {
  required String tipo, // 'cliente' | 'conductor'
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = tipo == 'conductor' ? _kKeyConductor : _kKeyCliente;
  final count = (prefs.getInt(key) ?? 0) + 1;
  await prefs.setInt(key, count);

  final debeMostrar = count == 1 || count % 3 == 0;
  if (!debeMostrar) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _SugerenciaSheet(tipo: tipo),
  );
}

class _SugerenciaSheet extends StatefulWidget {
  const _SugerenciaSheet({required this.tipo});
  final String tipo;

  @override
  State<_SugerenciaSheet> createState() => _SugerenciaSheetState();
}

class _SugerenciaSheetState extends State<_SugerenciaSheet> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _estrellas = 0;
  bool _enviando = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _textCtrl.text.trim();
    if (texto.isEmpty && _estrellas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una calificación o escribe un comentario.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _enviando = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await SugerenciasService.instance.enviar(
        userId: uid,
        tipo: widget.tipo,
        mensaje: texto,
        estrellas: _estrellas,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo enviar. Intenta de nuevo.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 14),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Icono
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColores.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColores.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),

                const Text(
                  '¿Qué opinas de Ride?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tu opinión nos ayuda a mejorar el servicio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // Estrellas
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < _estrellas;
                    return GestureDetector(
                      onTap: () => setState(() => _estrellas = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 38,
                          color: filled
                              ? const Color(0xFFFFC107)
                              : Colors.grey.shade400,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),

                // Campo de texto
                TextField(
                  controller: _textCtrl,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 2,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _focusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'Escribe tu sugerencia o comentario (opcional)...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColores.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Botón Enviar
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _enviando
                          ? AppColores.primary.withValues(alpha: 0.6)
                          : AppColores.primary,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _enviando ? null : _enviar,
                    child: _enviando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Enviar sugerencia',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),

                // Botón Omitir
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Omitir',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
