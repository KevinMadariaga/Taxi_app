import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';

/// Los tres únicos estilos de botón válidos para pantallas de viaje
/// (conductor/pasajero) — reemplaza estilos inline sueltos por pantalla.
/// Un solo botón [RidePrimaryButton] por pantalla: el que hace avanzar el
/// viaje. Todo lo demás es [RideSecondaryButton] o [RidePillButton].
class RidePrimaryButton extends StatelessWidget {
  const RidePrimaryButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.pastel = false,
  });

  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// `true`: variante suave (fondo `brand400`, mismo naranja que el
  /// círculo del vehículo en `BarraProgresoDireccional`) en vez del sólido
  /// `brand700` — para fases donde el CTA no debe leerse tan "urgente"
  /// (ej. "Ya llegué al punto").
  final bool pastel;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    const contentColor = AppColores.textWhite;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColores.ink200;
            }
            if (pastel) {
              return states.contains(WidgetState.pressed)
                  ? AppColores.brand500
                  : AppColores.brand400;
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColores.brand900;
            }
            return AppColores.brand700;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColores.ink500;
            }
            return contentColor;
          }),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: contentColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: contentColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: contentColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class RideSecondaryButton extends StatelessWidget {
  const RideSecondaryButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Cantidad a mostrar en la burbuja roja sobre [icon] (p.ej. mensajes sin
  /// leer). `0` no dibuja nada.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          highlightColor: AppColores.ink50,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColores.ink500, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 17, color: AppColores.ink700),
                      if (badgeCount > 0)
                        Positioned(
                          top: -5,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(
                              minWidth: 14,
                              minHeight: 14,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              badgeCount > 9 ? '9+' : '$badgeCount',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColores.ink700,
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

class RidePillButton extends StatelessWidget {
  const RidePillButton({super.key, required this.text, required this.onPressed});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColores.ink200, width: 0.5),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColores.ink700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
