import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';

/// Muestra el estado actual de la solicitud en tiempo real con una línea de
/// tiempo (timeline). Escucha el documento `solicitudes/{id}` en Firestore.
class EstadoSolicitudView extends StatelessWidget {
  EstadoSolicitudView({super.key, required this.solicitudId})
    : _stream = TripTrackingFirebaseService().watchSolicitudRaw(solicitudId);

  final String solicitudId;
  final Stream<Map<String, dynamic>> _stream;

  static const List<_PasoEstado> _pasos = [
    _PasoEstado(
      SolicitudEstado.buscando,
      'Buscando conductor',
      'Estamos asignando un conductor para tu viaje.',
      Icons.search_rounded,
    ),
    _PasoEstado(
      SolicitudEstado.asignado,
      'Conductor asignado',
      'Un conductor aceptó tu solicitud.',
      Icons.person_pin_circle_rounded,
    ),
    _PasoEstado(
      SolicitudEstado.enEspera,
      'En espera',
      'El conductor está por iniciar el viaje.',
      Icons.hourglass_top_rounded,
    ),
    _PasoEstado(
      SolicitudEstado.enCamino,
      'En camino',
      'El conductor va hacia tu punto de recogida.',
      Icons.directions_car_filled_rounded,
    ),
    _PasoEstado(
      SolicitudEstado.enRuta,
      'En ruta al destino',
      'Vas en camino hacia tu destino.',
      Icons.navigation_rounded,
    ),
    _PasoEstado(
      SolicitudEstado.completado,
      'Completado',
      'Llegaste a tu destino.',
      Icons.flag_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
        title: const Text(
          'Estado de mi solicitud',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColores.primary),
            );
          }

          final data = snapshot.data;
          final raw = (data?['estado'] ?? data?['status'] ?? '').toString();
          final estado = SolicitudEstado.normalize(raw);

          if (estado == SolicitudEstado.cancelado ||
              estado == SolicitudEstado.sinRespuesta) {
            return _EstadoTerminal(
              cancelado: estado == SolicitudEstado.cancelado,
            );
          }

          final currentIndex = _pasos.indexWhere((p) => p.estado == estado);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            itemCount: _pasos.length,
            itemBuilder: (context, i) {
              final paso = _pasos[i];
              final completado = currentIndex >= 0 && i < currentIndex;
              final actual = i == currentIndex;
              return _TimelineTile(
                paso: paso,
                completado: completado,
                actual: actual,
                esUltimo: i == _pasos.length - 1,
              );
            },
          );
        },
      ),
    );
  }
}

class _PasoEstado {
  const _PasoEstado(this.estado, this.titulo, this.descripcion, this.icono);
  final String estado;
  final String titulo;
  final String descripcion;
  final IconData icono;
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.paso,
    required this.completado,
    required this.actual,
    required this.esUltimo,
  });

  final _PasoEstado paso;
  final bool completado;
  final bool actual;
  final bool esUltimo;

  @override
  Widget build(BuildContext context) {
    final activo = completado || actual;
    final color = actual
        ? AppColores.buttonPrimary
        : (completado ? AppColores.success : AppColores.grey400);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: activo
                      ? color.withValues(alpha: 0.15)
                      : AppColores.grey200,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: actual ? 2.5 : 1.5),
                ),
                child: Icon(
                  completado ? Icons.check_rounded : paso.icono,
                  color: color,
                  size: 20,
                ),
              ),
              if (!esUltimo)
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: completado ? AppColores.success : AppColores.grey300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    paso.titulo,
                    style: TextStyle(
                      fontWeight: actual ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                      color: activo
                          ? AppColores.textPrimary
                          : AppColores.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    paso.descripcion,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  if (actual) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColores.buttonPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Estado actual',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColores.buttonPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoTerminal extends StatelessWidget {
  const _EstadoTerminal({required this.cancelado});
  final bool cancelado;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColores.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cancel_outlined,
                color: AppColores.error,
                size: 48,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              cancelado ? 'Solicitud cancelada' : 'Sin respuesta',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              cancelado
                  ? 'Tu solicitud de viaje fue cancelada.'
                  : 'Ningún conductor respondió a tu solicitud.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColores.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
