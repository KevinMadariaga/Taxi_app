import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/core/app_colores.dart';

class HistorialConductor extends StatefulWidget {
  const HistorialConductor({super.key});

  @override
  HistorialConductorState createState() => HistorialConductorState();
}

class HistorialConductorState extends State<HistorialConductor> {
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
    
    // Extraer nombre del cliente del objeto cliente
    String cliente = 'Cliente';
    final clienteObj = data['cliente'];
    if (clienteObj is Map && clienteObj['name'] != null) {
      cliente = clienteObj['name'].toString();
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
    final String conductorId = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial de Viajes"),
        backgroundColor: Colors.amber,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('historial viajes')
            .where('conductor.id', isEqualTo: conductorId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          var allViajes = snapshot.data?.docs ?? [];
          
          // Ordenar manualmente por completedAt
          allViajes.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['completedAt'] as Timestamp?;
            final bTime = bData['completedAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // Descendente
          });

          if (allViajes.isEmpty) {
            return const Center(child: Text("No hay viajes registrados."));
          }

          // Calcular promedio de calificaciones
          double promedioCalificacion = 0.0;
          int totalCalificaciones = 0;
          for (var viaje in allViajes) {
            final data = viaje.data() as Map<String, dynamic>;
            final calificacionObj = data['calificacion'];
            if (calificacionObj is Map && calificacionObj['score'] != null) {
              final score = (calificacionObj['score'] as num).toDouble();
              promedioCalificacion += score;
              totalCalificaciones++;
            }
          }
          if (totalCalificaciones > 0) {
            promedioCalificacion = promedioCalificacion / totalCalificaciones;
          }

          return Column(
            children: [
              // Tarjeta de calificación promedio
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu Calificación',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColores.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          promedioCalificacion.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Basado en $totalCalificaciones viajes',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColores.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Mostrar estrellas
                    Column(
                      children: [
                        Row(
                          children: List.generate(5, (index) {
                            final esStar = index < promedioCalificacion.toInt();
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Icon(
                                Icons.star,
                                size: 24,
                                color: esStar ? Colors.amber[600] : Colors.grey[300],
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Lista de viajes
              Expanded(
                child: ListView.builder(
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
