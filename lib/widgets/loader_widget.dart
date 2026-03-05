import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:taxi_app/core/app_colores.dart';

class LoaderWidget extends StatelessWidget {
  final String text;
  final Alignment alignment;
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;

  const LoaderWidget({
    Key? key,
    this.text = 'Obteniendo ubicación...',
    this.alignment = Alignment.center,
    this.top,
    this.bottom,
    this.left,
    this.right,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget loaderContent = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SpinKitCircle(
          color: AppColores.buttonPrimary,
          size: 60.0,
        ),
        const SizedBox(height: 18),
        Text(
          text,
          style: const TextStyle(
            color: AppColores.textPrimary,
            fontSize: 16,
          ),
        ),
      ],
    );

    // Si se especifica alguna posición, usar Positioned
    if (top != null || bottom != null || left != null || right != null) {
      return Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        child: loaderContent,
      );
    }
    // Si no, usar Align
    return Align(
      alignment: alignment,
      child: loaderContent,
    );
  }
}
