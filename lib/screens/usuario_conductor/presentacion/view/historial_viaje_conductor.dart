import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/historial_conductor_viewmodel.dart';
import 'package:taxi_app/widgets/historial/historial_widgets.dart';
import 'historial_detalle_conductor.dart';

class HistorialConductor extends StatefulWidget {
  const HistorialConductor({super.key});

  @override
  HistorialConductorState createState() => HistorialConductorState();
}

class HistorialConductorState extends State<HistorialConductor> {
  final _vm = HistorialConductorViewModel();

  double? _lastSyncedAverageRating;
  int? _lastSyncedRatingsCount;
  bool _isSyncingConductorRating = false;

  void _scheduleConductorRatingSync({
    required double averageRating,
    required int ratingsCount,
  }) {
    final uid = _vm.conductorId;
    if (uid.isEmpty) return;
    if (_isSyncingConductorRating) return;

    final avgRounded = double.parse(averageRating.toStringAsFixed(2));
    if (_lastSyncedAverageRating == avgRounded &&
        _lastSyncedRatingsCount == ratingsCount) {
      return;
    }

    _isSyncingConductorRating = true;
    unawaited(
      _vm
          .sincronizarCalificacion(
            uid: uid,
            averageRating: avgRounded,
            ratingsCount: ratingsCount,
          )
          .then((_) {
            _lastSyncedAverageRating = avgRounded;
            _lastSyncedRatingsCount = ratingsCount;
          })
          .catchError((_) {})
          .whenComplete(() => _isSyncingConductorRating = false),
    );
  }

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> data) async {
    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await _vm.obtenerDireccion(destinoRaw);
    if (!context.mounted) return;

    String cliente = 'Cliente';
    final clienteObj = data['cliente'];
    if (clienteObj is Map) {
      cliente =
          (clienteObj['name'] ?? clienteObj['nombre'] ?? cliente).toString();
    }

    showDialog(
      context: context,
      builder: (_) => DetalleViajeDialog(
        destino: destino,
        persona: cliente,
        tituloPersona: 'Cliente',
        calificacion: _vm.extraerCalificacion(data).clamp(0, 5).toDouble(),
        valor: formatPesos(_vm.extraerValorServicio(data)),
        metodoPago: (data['metodoPago'] ?? data['metodo_pago'] ?? 'efectivo')
            .toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conductorId = _vm.conductorId;

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text(
          'Historial de Viajes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: AppColores.primary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AppColores.primary,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.analytics_rounded),
        label: const Text('Ver ganancias'),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  HistorialDetalleConductor(conductorId: conductorId),
            ),
          );
        },
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _vm.cargarHistorial(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColores.primary),
            );
          }
          if (snapshot.hasError) {
            return HistorialEstadoMensaje(
              icon: Icons.error_outline_rounded,
              titulo: 'Ocurrió un error',
              subtitulo: '${snapshot.error}',
            );
          }

          final viajes = snapshot.data ?? [];

          double scoreTotal = 0.0;
          int ratedCount = 0;
          double totalGanado = 0.0;
          for (final viaje in viajes) {
            final score = _vm.extraerCalificacion(viaje).clamp(0, 5).toDouble();
            if (score > 0) {
              scoreTotal += score;
              ratedCount++;
            }
            totalGanado += _vm.extraerValorServicio(viaje);
          }
          final promedio = ratedCount > 0 ? (scoreTotal / ratedCount) : 0.0;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleConductorRatingSync(
              averageRating: promedio,
              ratingsCount: ratedCount,
            );
          });

          if (viajes.isEmpty) {
            return const HistorialEstadoMensaje(
              icon: Icons.history_rounded,
              titulo: 'Sin viajes registrados',
              subtitulo: 'Tus viajes completados aparecerán aquí.',
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                children: [
                  _ResumenConductor(
                    totalViajes: viajes.length,
                    promedio: promedio,
                    totalGanado: totalGanado,
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                      itemCount: viajes.length,
                      itemBuilder: (context, index) {
                        final data = viajes[index];
                        final destinoField = data['destino'];
                        return HistorialViajeCard(
                          destinoFuture: _vm.obtenerDireccion(destinoField),
                          destinoFallback: _fallbackDestino(destinoField),
                          fecha: _vm.formatarHoraFin(data),
                          valor: formatPesos(_vm.extraerValorServicio(data)),
                          calificacion: _vm
                              .extraerCalificacion(data)
                              .clamp(0, 5)
                              .toDouble(),
                          onTap: () => _mostrarDetalle(context, data),
                          isMoto: (data['tipoVehiculo'] ?? '').toString().toLowerCase() == 'moto',
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _fallbackDestino(dynamic field) {
  if (field is Map) {
    return (field['title']?.toString() ??
            field['address']?.toString() ??
            'Destino')
        .toString();
  }
  return field?.toString() ?? 'Destino';
}

class _ResumenConductor extends StatelessWidget {
  const _ResumenConductor({
    required this.totalViajes,
    required this.promedio,
    required this.totalGanado,
  });

  final int totalViajes;
  final double promedio;
  final double totalGanado;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Row(
        children: [
          _ResumenItem(
            icon: Icons.directions_car_rounded,
            valor: totalViajes.toString(),
            label: 'Viajes',
            color: AppColores.primary,
          ),
          const _SeparadorVertical(),
          _ResumenItem(
            icon: Icons.star_rounded,
            valor: promedio > 0 ? promedio.toStringAsFixed(1) : '–',
            label: 'Calificación',
            color: AppColores.primary,
          ),
          const _SeparadorVertical(),
          _ResumenItem(
            icon: Icons.payments_rounded,
            valor: formatPesos(totalGanado),
            label: 'Ganado',
            color: AppColores.success,
          ),
        ],
      ),
    );
  }
}

class _ResumenItem extends StatelessWidget {
  const _ResumenItem({
    required this.icon,
    required this.valor,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String valor;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColores.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeparadorVertical extends StatelessWidget {
  const _SeparadorVertical();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 38, color: AppColores.borderSubtle);
  }
}
