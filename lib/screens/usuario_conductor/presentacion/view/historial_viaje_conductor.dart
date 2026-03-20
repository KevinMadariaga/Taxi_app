import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'historial_detalle_conductor.dart';

class HistorialConductor extends StatefulWidget {
  const HistorialConductor({super.key});

  @override
  HistorialConductorState createState() => HistorialConductorState();
}

class HistorialConductorState extends State<HistorialConductor> {
  // Nota: este estado ya no usa filtros; mostramos solo la lista de solicitudes.
  double? _lastSyncedAverageRating;
  int? _lastSyncedRatingsCount;
  bool _isSyncingConductorRating = false;

  void _scheduleConductorRatingSync({
    required String conductorId,
    required double averageRating,
    required int ratingsCount,
  }) {
    if (conductorId.isEmpty) return;
    if (_isSyncingConductorRating) return;

    final avgRounded = double.parse(averageRating.toStringAsFixed(2));
    if (_lastSyncedAverageRating == avgRounded &&
        _lastSyncedRatingsCount == ratingsCount) {
      return;
    }

    _isSyncingConductorRating = true;
    unawaited(
      _syncConductorRating(
        conductorId: conductorId,
        averageRating: avgRounded,
        ratingsCount: ratingsCount,
      ),
    );
  }

  Future<void> _syncConductorRating({
    required String conductorId,
    required double averageRating,
    required int ratingsCount,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('conductor')
          .doc(conductorId)
          .set({
            'calificacionPromedio': averageRating,
            'totalCalificaciones': ratingsCount,
            'ultimaActualizacionCalificacion': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      _lastSyncedAverageRating = averageRating;
      _lastSyncedRatingsCount = ratingsCount;
    } catch (_) {
    } finally {
      _isSyncingConductorRating = false;
    }
  }

  bool _isCompletedStatus(Map<String, dynamic> data) {
    final estado = (data['estado'] ?? data['status'] ?? '')
        .toString()
        .toLowerCase();
    return estado == 'completado' || estado.contains('complet');
  }

  double _extractServiceValue(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) {
      final total = tarifa['total'];
      if (total is num) return total.toDouble();
      return double.tryParse(total.toString()) ?? 0.0;
    }

    final valor = data['valor'];
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor?.toString() ?? '') ?? 0.0;
  }

  double _extractRatingScore(Map<String, dynamic> data) {
    final raw = data['calificacion'] ?? data['calificacion_cliente'];
    if (raw is Map) {
      final score = raw['score'] ?? raw['puntaje'] ?? raw['valor'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '') ?? 0.0;
    }
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  String _formatMoney(double value) {
    final rounded = value.round();
    final raw = rounded.toString();
    return raw.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }

  String formatoFechaHora(Timestamp timestamp) {
    final fecha = timestamp.toDate().toUtc().subtract(const Duration(hours: 5));
    return "${fecha.day.toString().padLeft(2, '0')}/"
        "${fecha.month.toString().padLeft(2, '0')}/"
        "${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:"
        "${fecha.minute.toString().padLeft(2, '0')}";
  }

  Future<String> obtenerDireccion(dynamic ubicacion) async {
    if (ubicacion is GeoPoint) {
      try {
        final placemarks = await placemarkFromCoordinates(
          ubicacion.latitude,
          ubicacion.longitude,
        );
        final p = placemarks.first;
        return "${p.street ?? ''}, ${p.locality ?? ''}";
      } catch (_) {
        return "Dirección no disponible";
      }
    } else if (ubicacion is Map) {
      // Puede venir como { 'title': 'Lugar', 'lat': x, 'lng': y }
      if (ubicacion['title'] != null &&
          (ubicacion['title'] as String).isNotEmpty) {
        return ubicacion['title'].toString();
      }
      final latObj = ubicacion['lat'];
      final lngObj = ubicacion['lng'];
      if (latObj != null && lngObj != null) {
        final lat = (latObj is num)
            ? latObj.toDouble()
            : double.tryParse(latObj.toString());
        final lng = (lngObj is num)
            ? lngObj.toDouble()
            : double.tryParse(lngObj.toString());
        if (lat != null && lng != null) {
          try {
            final placemarks = await placemarkFromCoordinates(lat, lng);
            final p = placemarks.first;
            return "${p.street ?? ''}, ${p.locality ?? ''}";
          } catch (_) {
            return "Dirección no disponible";
          }
        }
      }
      return "Destino desconocido";
    } else if (ubicacion is String) {
      return ubicacion;
    } else {
      return "Origen desconocido";
    }
  }

  void mostrarDetalle(BuildContext context, Map<String, dynamic> data) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth * 0.04;

    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await obtenerDireccion(destinoRaw);
    final calificacionScore = _extractRatingScore(data).clamp(0, 5);
    final estrellasLlenas = calificacionScore.floor();
    final tieneMedia = (calificacionScore - estrellasLlenas) >= 0.5;

    // Extraer nombre del cliente del objeto cliente
    String cliente = 'Cliente';
    final clienteObj = data['cliente'];
    if (clienteObj is Map) {
      cliente = (clienteObj['name'] ?? clienteObj['nombre'] ?? cliente)
          .toString();
    }

    final precio = _extractServiceValue(data);

    final metodoPago = (data['metodoPago'] ?? data['metodo_pago'] ?? 'efectivo')
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
                      "DETALLE DEL VIAJE",
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

                    // Cliente centrado
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

                    // Calificación con estrellas
                    Text(
                      "Calificación del viaje",
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
                        final esMedia = index == estrellasLlenas && tieneMedia;
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
                      "VALOR DEL SERVICIO",
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "\$ ${_formatMoney(precio)}",
                      style: TextStyle(
                        fontSize: fontSize + 6,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Método de pago
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

              // Cerrar (icono arriba derecha)
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
    final String conductorId = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial de Viajes"),
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
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('solicitudes')
            .where('conductor.id', isEqualTo: conductorId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          // Filtrar solo solicitudes con estado 'completado'
          var allViajes = (snapshot.data?.docs ?? []).where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _isCompletedStatus(data);
          }).toList();

          // Ordenar manualmente por fecha de finalización (completedAt o fecha de terminacion)
          allViajes.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime =
                (aData['completedAt'] ?? aData['fecha de terminacion'])
                    as Timestamp?;
            final bTime =
                (bData['completedAt'] ?? bData['fecha de terminacion'])
                    as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // Descendente
          });

          double scoreTotal = 0.0;
          int ratedCount = 0;
          for (final viaje in allViajes) {
            final viajeData = viaje.data() as Map<String, dynamic>;
            final score = _extractRatingScore(viajeData).clamp(0, 5).toDouble();
            if (score > 0) {
              scoreTotal += score;
              ratedCount++;
            }
          }
          final promedio = ratedCount > 0 ? (scoreTotal / ratedCount) : 0.0;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleConductorRatingSync(
              conductorId: conductorId,
              averageRating: promedio,
              ratingsCount: ratedCount,
            );
          });

          if (allViajes.isEmpty) {
            return const Center(child: Text("No hay viajes registrados."));
          }

          // Solo mostramos la lista completa de solicitudes (sin tarjeta de resumen ni filtros)
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: allViajes.length,
            itemBuilder: (context, index) {
              final data = allViajes[index].data() as Map<String, dynamic>;
              final destinoRaw = data['destino'];
              final destinoFuture = obtenerDireccion(destinoRaw);
              final horaFin =
                  (data['completedAt'] ?? data['fecha de terminacion'])
                      as Timestamp?;
              final valorServicio = _extractServiceValue(data);
              final calificacion = _extractRatingScore(data).clamp(0, 5);
              // final duracion = data['duracion minutos']?.toString() ?? '-';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                (snapshot.data ??
                                (destinoRaw is Map
                                    ? (destinoRaw['title']?.toString() ??
                                          destinoRaw['address']?.toString() ??
                                          'Destino')
                                    : (destinoRaw?.toString() ?? 'Destino')));
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
                            if (horaFin != null)
                              Text("${formatoFechaHora(horaFin)}"),
                          ],
                        ),
                        onTap: () => mostrarDetalle(context, data),
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
                                _formatMoney(valorServicio),
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
