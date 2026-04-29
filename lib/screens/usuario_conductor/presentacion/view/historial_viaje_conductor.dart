import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/historial_conductor_viewmodel.dart';
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
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth * 0.04;

    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await _vm.obtenerDireccion(destinoRaw);
    if (!context.mounted) return;

    final calificacionScore = _vm.extraerCalificacion(data).clamp(0, 5);
    final estrellasLlenas = calificacionScore.floor();
    final tieneMedia = (calificacionScore - estrellasLlenas) >= 0.5;

    String cliente = 'Cliente';
    final clienteObj = data['cliente'];
    if (clienteObj is Map) {
      cliente =
          (clienteObj['name'] ?? clienteObj['nombre'] ?? cliente).toString();
    }

    final precio = _vm.extraerValorServicio(data);
    final metodoPago =
        (data['metodoPago'] ?? data['metodo_pago'] ?? 'efectivo')
            .toString()
            .toUpperCase();

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'DETALLE DEL VIAJE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize + 4,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 22,
                          color: AppColores.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            destino.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: fontSize + 5,
                              color: AppColores.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Column(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.amber,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cliente,
                          style: TextStyle(
                            fontSize: fontSize + 1,
                            fontWeight: FontWeight.w500,
                            color: AppColores.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Divider(color: Colors.grey[300]),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Calificación del viaje',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final esStar = index < estrellasLlenas;
                        final esMedia =
                            index == estrellasLlenas && tieneMedia;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            esStar
                                ? Icons.star
                                : esMedia
                                ? Icons.star_half
                                : Icons.star_border,
                            size: 32,
                            color: (esStar || esMedia)
                                ? Colors.amber[600]
                                : Colors.grey[300],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      calificacionScore > 0
                          ? calificacionScore.toStringAsFixed(1)
                          : 'Sin calificacion',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'VALOR DEL SERVICIO',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$ ${_vm.formatearDinero(precio)}',
                      style: TextStyle(
                        fontSize: fontSize + 6,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      metodoPago,
                      style: TextStyle(
                        fontSize: fontSize * 0.95,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  splashRadius: 20,
                  color: AppColores.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final conductorId = _vm.conductorId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Viajes'),
        backgroundColor: Colors.amber,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.analytics),
        label: const Text('Ver detalle'),
        backgroundColor: Colors.amber,
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allViajes = snapshot.data ?? [];

          double scoreTotal = 0.0;
          int ratedCount = 0;
          for (final viaje in allViajes) {
            final score = _vm.extraerCalificacion(viaje).clamp(0, 5).toDouble();
            if (score > 0) {
              scoreTotal += score;
              ratedCount++;
            }
          }
          final promedio = ratedCount > 0 ? (scoreTotal / ratedCount) : 0.0;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleConductorRatingSync(
              averageRating: promedio,
              ratingsCount: ratedCount,
            );
          });

          if (allViajes.isEmpty) {
            return const Center(child: Text('No hay viajes registrados.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: allViajes.length,
            itemBuilder: (context, index) {
              final data = allViajes[index];
              final destinoRaw = data['destino'];
              final destinoFuture = _vm.obtenerDireccion(destinoRaw);
              final horaFinStr = _vm.formatarHoraFin(data);
              final valorServicio = _vm.extraerValorServicio(data);
              final calificacion = _vm.extraerCalificacion(data).clamp(0, 5);

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        leading: const Icon(
                          Icons.local_taxi,
                          color: Colors.amber,
                        ),
                        title: FutureBuilder<String>(
                          future: destinoFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Text('Cargando...');
                            }
                            final text =
                                snapshot.data ??
                                (destinoRaw is Map
                                    ? (destinoRaw['title']?.toString() ??
                                          destinoRaw['address']?.toString() ??
                                          'Destino')
                                    : (destinoRaw?.toString() ?? 'Destino'));
                            return Text(
                              text.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (horaFinStr != null) Text(horaFinStr),
                          ],
                        ),
                        onTap: () => _mostrarDetalle(context, data),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.attach_money,
                                size: 18,
                                color: Colors.green,
                              ),
                              Text(
                                _vm.formatearDinero(valorServicio),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 16,
                                color: calificacion > 0
                                    ? Colors.amber[700]
                                    : Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                calificacion > 0
                                    ? calificacion.toStringAsFixed(1)
                                    : '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColores.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
