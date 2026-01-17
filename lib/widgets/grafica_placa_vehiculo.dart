import 'package:flutter/material.dart';

/// Widget que muestra la placa del vehículo con estilo realista de placa colombiana.
class VehiclePlateWidget extends StatelessWidget {
  final String placa;
  final double? width;
  final double? height;

  const VehiclePlateWidget({
    super.key,
    required this.placa,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Altura base de la placa; si no se especifica, usa 30px aprox.
    final h = height ?? 30.0;
    // Relación ancho/alto típica de una placa (más horizontal).
    final w = width ?? h * 2.5;

    final normalizedPlate = placa.toUpperCase().replaceAll(' ', '');

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255), // blanco tipo placa colombiana
        border: Border.all(color: Colors.black, width: 2.2),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pequeños "remaches" en las esquinas
          Positioned(
            left: 6,
            top: 6,
            child: _screwDot(),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: _screwDot(),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: _screwDot(),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: _screwDot(),
          ),
          // Contenido principal
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Franja superior con el país
              Padding(
                padding: EdgeInsets.only(bottom: h * 0.02),
                child: Text(
                  'COLOMBIA',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: h * 0.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
              // Número de placa centrado y grande
              Text(
                normalizedPlate,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: h * 0.35,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3.5,
                  fontFamily: 'Courier',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Punto decorativo que simula el tornillo de la placa.
Widget _screwDot() {
  return Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
  );
}
