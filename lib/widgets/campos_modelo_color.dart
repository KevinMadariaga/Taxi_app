import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Colores más comunes, para elegir con un toque. El campo sigue aceptando
/// cualquier otro.
const List<(String, Color)> _coloresRapidos = [
  ('Blanco', Color(0xFFF5F5F5)),
  ('Negro', Color(0xFF1C1C1C)),
  ('Gris', Color(0xFF8A8F98)),
  ('Plata', Color(0xFFC9CDD2)),
  ('Rojo', Color(0xFFD32F2F)),
  ('Azul', Color(0xFF1E5BD8)),
];

/// Campos "Modelo" y "Color" del vehículo (registro de conductor, Mis
/// vehículos, Editar perfil): mismo aspecto y mismas ayudas en todos lados.
class CamposModeloColor extends StatelessWidget {
  const CamposModeloColor({
    super.key,
    required this.modeloController,
    required this.colorController,
    required this.tipo,
    this.errorModelo,
    this.errorColor,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController modeloController;
  final TextEditingController colorController;

  /// "carro" / "moto", para los textos de ayuda.
  final String tipo;
  final String? errorModelo;
  final String? errorColor;
  final bool enabled;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colorActual = colorController.text.trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Etiqueta(
          'Marca y modelo',
          'Como lo reconocería el pasajero. Ej. '
              '${tipo == 'moto' ? 'Yamaha NMAX' : 'Chevrolet Spark'}.',
        ),
        _Campo(
          controller: modeloController,
          hint: tipo == 'moto' ? 'Ej. Yamaha NMAX' : 'Ej. Chevrolet Spark',
          icono: tipo == 'moto'
              ? Icons.two_wheeler_rounded
              : Icons.directions_car_outlined,
          error: errorModelo,
          enabled: enabled,
          capitalizacion: TextCapitalization.words,
          formatters: [LengthLimitingTextInputFormatter(40)],
          onChanged: onChanged,
        ),
        _Error(errorModelo),
        const SizedBox(height: 18),
        const _Etiqueta('Color', 'Toca uno o escríbelo si es otro.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (nombre, color) in _coloresRapidos)
              ChoiceChip(
                avatar: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.grey400),
                  ),
                ),
                label: Text(nombre),
                showCheckmark: false,
                selected: colorActual == nombre.toLowerCase(),
                selectedColor: AppColores.primary.withValues(alpha: 0.2),
                backgroundColor: palette.surface,
                side: BorderSide(
                  color: colorActual == nombre.toLowerCase()
                      ? AppColores.primary
                      : palette.borderSubtle,
                ),
                shape: const StadiumBorder(),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
                onSelected: !enabled
                    ? null
                    : (_) {
                        colorController.text = nombre;
                        onChanged?.call();
                      },
              ),
          ],
        ),
        const SizedBox(height: 10),
        _Campo(
          controller: colorController,
          hint: 'Otro color',
          icono: Icons.palette_outlined,
          error: errorColor,
          enabled: enabled,
          capitalizacion: TextCapitalization.words,
          formatters: [LengthLimitingTextInputFormatter(20)],
          onChanged: onChanged,
        ),
        _Error(errorColor),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto, this.ayuda);

  final String texto;
  final String ayuda;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            ayuda,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo({
    required this.controller,
    required this.hint,
    required this.icono,
    required this.error,
    required this.enabled,
    required this.capitalizacion,
    required this.formatters,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icono;
  final String? error;
  final bool enabled;
  final TextCapitalization capitalizacion;
  final List<TextInputFormatter> formatters;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final conError = error != null;
    OutlineInputBorder borde(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      textCapitalization: capitalizacion,
      inputFormatters: formatters,
      onChanged: (_) => onChanged?.call(),
      cursorColor: AppColores.primary,
      style: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontWeight: FontWeight.w400,
          color: palette.textSecondary.withValues(alpha: 0.7),
        ),
        prefixIcon: Icon(icono, color: palette.textSecondary),
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        enabledBorder: borde(
          conError ? AppColores.error : palette.grey300,
          conError ? 1.8 : 1.2,
        ),
        focusedBorder: borde(
          conError ? AppColores.error : AppColores.primary,
          1.8,
        ),
        disabledBorder: borde(palette.grey200, 1.2),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.mensaje);

  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: mensaje == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppColores.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mensaje!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColores.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
