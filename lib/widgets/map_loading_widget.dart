import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

class MapLoadingWidget extends StatelessWidget {
  final String message;

  const MapLoadingWidget({
    super.key,
    this.message = 'Cargando mapa...',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColores.primary),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
