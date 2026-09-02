import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/visor_foto_pantalla_completa.dart';

/// Avatar + nombre + dirección del cliente — renderizado inline en la
/// tarjeta (antes solo aparecía si el conductor abría el sheet de
/// detalles, wireado además solo en la fase de recogida).
class ClienteHeaderRow extends StatelessWidget {
  const ClienteHeaderRow({
    super.key,
    required this.nombre,
    required this.photoUrl,
    required this.direccion,
  });

  final String nombre;
  final String? photoUrl;
  final String direccion;

  static String _iniciales(String nombre) {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    if (partes.isEmpty) return '?';
    final primera = partes.first[0];
    final segunda = partes.length > 1 ? partes.last[0] : '';
    return (primera + segunda).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tienePhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Row(
      children: [
        GestureDetector(
          onTap: tienePhoto
              ? () => mostrarFotoPantallaCompleta(context, photoUrl!)
              : null,
          child: CircleAvatar(
            radius: 28,
            backgroundColor: AppColores.brand200,
            backgroundImage: tienePhoto ? NetworkImage(photoUrl!) : null,
            child: tienePhoto
                ? null
                : Text(
                    _iniciales(nombre),
                    style: const TextStyle(
                      color: AppColores.brand900,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColores.ink900,
                ),
              ),
              if (direccion.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 14,
                      color: AppColores.ink500,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        direccion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColores.ink500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
