import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class CalificacionSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Califica el servicio',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Selecciona de 1 a 5 estrellas para continuar.',
              style: TextStyle(
                color: AppColores.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return InkResponse(
                  onTap: () => onCalificacionChanged(starValue.toDouble()),
                  child: Icon(
                    calificacion >= starValue ? Icons.star : Icons.star_border,
                    color: AppColores.buttonPrimary,
                    size: 36,
                  ),
                );
              }),
            ),
            if (calificacion > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${calificacion.toStringAsFixed(0)} de 5 estrellas',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColores.buttonPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (requiereComentario) ...[
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('comentario_baja_calificacion'),
                initialValue: comentarioInicial,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: 'Cuentanos que paso... (obligatorio)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: onComentarioChanged,
                onEditingComplete: () => FocusScope.of(context).unfocus(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
