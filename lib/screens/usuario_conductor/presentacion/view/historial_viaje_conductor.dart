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
      if (ubicacion['title'] != null && (ubicacion['title'] as String).isNotEmpty) {
        return ubicacion['title'].toString();
      }
      final latObj = ubicacion['lat'];
      final lngObj = ubicacion['lng'];
      if (latObj != null && lngObj != null) {
        final lat = (latObj is num) ? latObj.toDouble() : double.tryParse(latObj.toString());
        final lng = (lngObj is num) ? lngObj.toDouble() : double.tryParse(lngObj.toString());
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
    final duracion = data['duracion minutos']?.toString() ?? '-';
    
    // Extraer score de la calificación
    int calificacionNum = 0;
    final calificacionObj = data['calificacion'] ?? data['calificacion_cliente'];
    if (calificacionObj is Map && calificacionObj['score'] != null) {
      calificacionNum = (calificacionObj['score'] as num).toInt();
    }
    
    // Extraer nombre del cliente del objeto cliente
    String cliente = 'Cliente';
    final clienteObj = data['cliente'];
    if (clienteObj is Map) {
      cliente = (clienteObj['name'] ?? clienteObj['nombre'] ?? cliente).toString();
    }
    
    // Extraer precio: preferir 'tarifa.total', si no usar 'valor'
    String precio = '---';
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) {
      precio = tarifa['total'].toString();
    } else if (data['valor'] != null) {
      precio = data['valor'].toString();
    }
    
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
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.analytics),
        label: const Text('Ver detalle'),
        backgroundColor: Colors.amber,
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HistorialDetalleConductor(
              conductorId: conductorId,
            ),
          ));
        },
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes')
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
          
          // Ordenar manualmente por fecha de finalización (completedAt o fecha de terminacion)
          allViajes.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = (aData['completedAt'] ?? aData['fecha de terminacion']) as Timestamp?;
            final bTime = (bData['completedAt'] ?? bData['fecha de terminacion']) as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // Descendente
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
                final horaFin = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
                final duracion = data['duracion minutos']?.toString() ?? '-';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.local_taxi, color: Colors.amber),
                    title: FutureBuilder<String>(
                      future: destinoFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text('Cargando...');
                        }
                        final text = snapshot.data ??
                            (destinoRaw is Map
                                ? (destinoRaw['title']?.toString() ?? destinoRaw['address']?.toString() ?? 'Destino')
                                : (destinoRaw?.toString() ?? 'Destino'));
                        return Text(text);
                      },
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (horaFin != null) Text("📅 Finalizado: ${formatoFechaHora(horaFin)}"),
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
