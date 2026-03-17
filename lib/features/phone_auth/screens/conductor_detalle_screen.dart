import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../services/user_data_service.dart';

class ConductorDetalleScreen extends StatelessWidget {
  const ConductorDetalleScreen({super.key, required this.conductorId});

  final String conductorId;

  @override
  Widget build(BuildContext context) {
    final userDataService = UserDataService();

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Detalle de conductor'),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder(
          stream: userDataService.streamConductor(conductorId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Error cargando conductor: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final conductor = snapshot.data;
            if (conductor == null) {
              return const Center(child: Text('Conductor no encontrado.'));
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: AppColores.primary,
                  backgroundImage: conductor.fotoConductor.isNotEmpty
                      ? NetworkImage(conductor.fotoConductor)
                      : null,
                  child: conductor.fotoConductor.isEmpty
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    conductor.nombre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Telefono', value: conductor.telefono),
                _DetailRow(label: 'Placa', value: conductor.placa),
                _DetailRow(label: 'Estado', value: conductor.estado),
                const SizedBox(height: 12),
                const Text(
                  'Foto del vehiculo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: conductor.fotoVehiculo.isNotEmpty
                        ? Image.network(
                            conductor.fotoVehiculo,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: AppColores.grey100,
                            child: const Icon(Icons.directions_car, size: 42),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColores.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
