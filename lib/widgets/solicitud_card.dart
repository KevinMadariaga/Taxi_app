import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/data/models/solicitud_id.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';

class SolicitudCard extends StatelessWidget {
  final SolicitudItem solicitud;
  final bool isLoading;
  final void Function(PreviewSolicitud)? onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onCancel;
  final VoidCallback? onClose;
  final bool expanded;

  const SolicitudCard({
    super.key,
    required this.solicitud,
    this.isLoading = false,
    this.onTap,
    this.onAccept,
    this.onCancel,
    this.onClose,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    // Mostrar distancia en metros calculada (desde ViewModel: distanciaKm)
    String cercania;
    if (solicitud.distanciaKm == null) {
      cercania = '—';
    } else {
      final metros = (solicitud.distanciaKm! * 1000).round();
      cercania = '$metros m';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap == null ? null : () => onTap!(PreviewSolicitud.fromSolicitud(solicitud)),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (context) {
                          final origenTitle = solicitud.origenTitle;
                          final origenAddress = solicitud.direccion;
                          final coords = solicitud.ubicacionInicial;
                          final mainName = origenTitle ?? (solicitud.nombreCliente ?? 'Ubicación');

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2.0, right: 8.0),
                                          child: Icon(Icons.location_on, size: 18, color: Colors.redAccent),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Recoger en', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColores.textPrimary,)),
                                              const SizedBox(height: 4),
                                              if (origenAddress != null && origenAddress.trim().isNotEmpty)
                                                 Text(
                                                mainName,
                                                style: const TextStyle(fontSize: 14,color: AppColores.textPrimary,),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Distancia', style: TextStyle(fontSize: 13 , color: AppColores.textPrimary,fontWeight: FontWeight.bold,)),
                                  const SizedBox(height: 3),
                                  Text(
                                    cercania,
                                    style: TextStyle(
                                      color: AppColores.textPrimary,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (expanded && onClose != null)
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.white.withOpacity(0.9),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }


}
