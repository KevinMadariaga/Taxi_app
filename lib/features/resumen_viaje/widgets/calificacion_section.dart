import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Sección de calificación del servicio (lado cliente).
/// - Estrellas seleccionables con etiqueta de feedback.
/// - Si la calificación es < 3, pide un comentario obligatorio.
/// - Al enfocar el comentario, centra el campo sobre el teclado y ofrece un
///   botón para cerrar el teclado, evitando que el contenido quede tapado.
class CalificacionSection extends StatefulWidget {
  const CalificacionSection({
    super.key,
    required this.calificacion,
    required this.onCalificacionChanged,
    required this.requiereComentario,
    required this.comentarioInicial,
    required this.onComentarioChanged,
  });

  final double calificacion;
  final ValueChanged<double> onCalificacionChanged;
  final bool requiereComentario;
  final String comentarioInicial;
  final ValueChanged<String> onComentarioChanged;

  @override
  State<CalificacionSection> createState() => _CalificacionSectionState();
}

class _CalificacionSectionState extends State<CalificacionSection> {
  final FocusNode _focus = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();
  late final TextEditingController _comentarioCtrl;

  static const _labels = <int, String>{
    1: 'Muy malo',
    2: 'Malo',
    3: 'Regular',
    4: 'Bueno',
    5: 'Excelente',
  };

  @override
  void initState() {
    super.initState();
    _comentarioCtrl = TextEditingController(text: widget.comentarioInicial);
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) return;
    // Centrar el campo cuando aparece el teclado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _fieldKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cal = widget.calificacion.round();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColores.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: AppColores.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Cómo estuvo tu viaje?',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColores.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tu opinión ayuda a mejorar el servicio.',
                        style: TextStyle(
                          color: AppColores.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (index) {
                final value = index + 1;
                final selected = cal >= value;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onCalificacionChanged(value.toDouble()),
                  child: AnimatedScale(
                    scale: selected ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      selected
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: selected
                          ? AppColores.primary
                          : AppColores.grey400,
                      size: 42,
                    ),
                  ),
                );
              }),
            ),
            if (cal > 0) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _labels[cal] ?? '',
                  style: const TextStyle(
                    color: AppColores.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: widget.requiereComentario
                  ? Padding(
                      key: _fieldKey,
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: _comentarioCtrl,
                        focusNode: _focus,
                        // Single-line para que el teclado del dispositivo
                        // muestre el botón "OK/Listo" que baja el teclado.
                        maxLines: 1,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: widget.onComentarioChanged,
                        onSubmitted: (_) => _focus.unfocus(),
                        onEditingComplete: () => _focus.unfocus(),
                        decoration: InputDecoration(
                          hintText: 'Cuéntanos qué pasó (obligatorio)',
                          filled: true,
                          fillColor: AppColores.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColores.borderSubtle,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColores.borderSubtle,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: AppColores.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
