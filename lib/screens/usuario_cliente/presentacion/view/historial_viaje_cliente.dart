import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';

import 'package:taxi_app/core/app_colores.dart';

class HistorialCliente extends StatefulWidget {
  const HistorialCliente({super.key});

  @override
  HistorialClienteState createState() => HistorialClienteState();
}

class HistorialClienteState extends State<HistorialCliente> {
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
    final destino = destinoRaw.toString().toLowerCase();
    final duracion = data['duracion minutos']?.toString() ?? '-';
    
    // Extraer score de la calificación
    int calificacionNum = 0;
    final calificacionObj = data['calificacion'];
    if (calificacionObj is Map && calificacionObj['score'] != null) {
      calificacionNum = (calificacionObj['score'] as num).toInt();
    }
    
    // Extraer nombre del conductor del objeto conductor
    String conductor = 'Conductor';
    final conductorObj = data['conductor'];
    if (conductorObj is Map && conductorObj['nombre'] != null) {
      conductor = conductorObj['nombre'].toString();
    }
    
    // Extraer precio del objeto tarifa
    String precio = '---';
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) {
      precio = tarifa['total'].toString();
    }
    
    final metodoPago = (data['metodoPago'] ?? 'efectivo')
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
                          size: 18,
                          color: AppColores.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            destino,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: fontSize * 0.98,
                              color: AppColores.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "⏳ Tiempo estimado: $duracion min",
                      style: TextStyle(
                        fontSize: fontSize * 0.95,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Conductor centrado
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
                          conductor,
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
                        final esStar = index < calificacionNum;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.star,
                            size: 32,
                            color: esStar ? Colors.amber[600] : Colors.grey[300],
                          ),
                        );
                      }),
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
                      "\$ $precio",
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial de Viajes"),
        backgroundColor: Colors.amber,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('historial viajes')
            .orderBy('completedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error al cargar los datos."));
          }

          final allViajes = snapshot.data?.docs ?? [];

          if (allViajes.isEmpty) {
            return const Center(child: Text("No hay viajes registrados."));
          }

          return ListView.builder(
            itemCount: allViajes.length,
            itemBuilder: (context, index) {
              final data = allViajes[index].data() as Map<String, dynamic>;

              final destino = data['destino'] ?? 'Destino';
              final horaFin = data['completedAt'] as Timestamp?;
              final duracion = data['duracion minutos']?.toString() ?? '-';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.local_taxi, color: Colors.amber),
                  title: Text("$destino"),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (horaFin != null)
                        Text("📅 Finalizado: ${formatoFechaHora(horaFin)}"),
                      Text("⏱ Duración: $duracion min"),
                    ],
                  ),
                  onTap: () => mostrarDetalle(context, data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
