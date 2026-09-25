import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final double? width;
  final double? height;
  final double? fontSize;
  final Widget? icon;
  final bool isLoading;
  final Color? color;
  final Color? textColor;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.width,
    this.height,
    this.fontSize,
    this.icon,
    this.isLoading = false,
    this.color,
    this.textColor,
    this.borderColor,
  });
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final buttonWidth = width ?? screenWidth * 0.8;
    final buttonHeight = height ?? screenHeight * 0.07;
    final textFontSize = fontSize ?? buttonHeight * 0.4;

    final isDisabled = onPressed == null || isLoading;
    final fondo = isDisabled
        ? context.palette.grey400
        : (color ?? AppColores.buttonPrimary);
    // Sin `textColor`, el contenido se elige según el fondo: antes era blanco
    // siempre, y sobre el ámbar por defecto (o el gris claro de deshabilitado
    // en modo claro) quedaba por debajo de 2:1. Deshabilitado el fondo es
    // siempre el gris, así que ahí manda el fondo y no el `textColor`.
    final contenido = isDisabled
        ? colorContenidoSobre(fondo)
        : (textColor ?? colorContenidoSobre(fondo));

    return SizedBox(
      width: buttonWidth,
      height: buttonHeight,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: fondo,
          disabledBackgroundColor: context.palette.grey400,
          side: borderColor != null ? BorderSide(color: borderColor!) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(contenido),
                    strokeWidth: 2,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 8)],
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: contenido,
                        fontSize: textFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
