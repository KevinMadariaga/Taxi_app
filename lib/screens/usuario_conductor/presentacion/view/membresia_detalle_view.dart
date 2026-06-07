import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Detalle de la membresía del conductor. Se abre al tocar la tarjeta
/// "Estás activo" en el perfil del conductor.
class MembresiaDetalleView extends StatelessWidget {
  const MembresiaDetalleView({super.key, required this.data});

  final Map<String, dynamic> data;

  String _fecha(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final activa =
        (data['membresia'] ?? '').toString().toLowerCase() == 'activa';
    final dias = data['membresiaDias'];
    final inicio = data['membresiaInicio'];
    final vence = data['membresiaVence'];

    int? diasRestantes;
    if (vence is Timestamp) {
      diasRestantes = vence.toDate().difference(DateTime.now()).inDays;
      if (diasRestantes < 0) diasRestantes = 0;
    }

    final color = activa ? AppColores.success : AppColores.error;

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Detalle de membresía'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(activa ? Icons.verified : Icons.cancel,
                          color: color, size: 48),
                      const SizedBox(height: 10),
                      Text(
                        activa ? 'Estás activo' : 'No estás activo',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activa
                            ? 'Tu membresía está activa.'
                            : 'Activa tu membresía para recibir viajes.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColores.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _DetalleTile(
                  icon: Icons.timelapse,
                  titulo: 'Días contratados',
                  valor: dias != null ? '$dias días' : '—',
                ),
                _DetalleTile(
                  icon: Icons.event_available,
                  titulo: 'Inicio',
                  valor: _fecha(inicio),
                ),
                _DetalleTile(
                  icon: Icons.event_busy,
                  titulo: 'Vence',
                  valor: _fecha(vence),
                ),
                _DetalleTile(
                  icon: Icons.hourglass_bottom,
                  titulo: 'Días restantes',
                  valor: activa && diasRestantes != null
                      ? '$diasRestantes días'
                      : '—',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetalleTile extends StatelessWidget {
  const _DetalleTile({
    required this.icon,
    required this.titulo,
    required this.valor,
  });

  final IconData icon;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColores.primary),
        title: Text(titulo,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        trailing: Text(valor,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
