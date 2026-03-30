import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:flutter/services.dart';

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
    } else if (ubicacion is Map) {
      // Puede venir como { 'title': 'Lugar', 'lat': x, 'lng': y }
      final title = ubicacion['title'];
      if (title is String && title.isNotEmpty) {
        return title;
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

  int _extraerCalificacion(Map<String, dynamic> data) {
    int calificacionNum = 0;
    final calificacionObj = data['calificacion cliente'] ??
        data['calificacion'] ??
        data['calificacion_cliente'] ??
        data['rating'];

    if (calificacionObj == null) return 0;

    if (calificacionObj is Map) {
      final score = calificacionObj['score'] ??
          calificacionObj['valor'] ??
          calificacionObj['rating'] ??
          calificacionObj['value'];
      if (score is num) {
        calificacionNum = score.toInt();
      } else if (score != null) {
        calificacionNum = int.tryParse(score.toString()) ?? 0;
      }
    } else if (calificacionObj is num) {
      calificacionNum = calificacionObj.toInt();
    } else if (calificacionObj is String) {
      calificacionNum = int.tryParse(calificacionObj) ?? 0;
    }

    return calificacionNum;
  }

  String _extraerNombreConductor(Map<String, dynamic> data) {
    final conductorObj = data['conductor'];
    if (conductorObj is Map && conductorObj['nombre'] != null) {
      return conductorObj['nombre'].toString();
    }
    return 'Conductor';
  }

  String _extraerPrecio(Map<String, dynamic> data) {
    String precio = '---';
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) {
      precio = tarifa['total'].toString();
    } else if (data['valor'] != null) {
      precio = data['valor'].toString();
    }
    return precio;
  }

  void mostrarDetalle(BuildContext context, Map<String, dynamic> data) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth * 0.04;

    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await obtenerDireccion(destinoRaw);
    final calificacionNum = _extraerCalificacion(data);
    final conductor = _extraerNombreConductor(data);
    final precio = _extraerPrecio(data);

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
                            destino.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: fontSize * 0.98,
                              color: AppColores.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
        title: const Text(
          "Historial de Viajes",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: Builder(
        builder: (context) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) {
            return const Center(child: Text("Usuario no autenticado."));
          }

          return FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('solicitudes')
                .where('cliente.id', isEqualTo: uid)
                .get(),
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

              return ListView.builder(
                itemCount: allViajes.length,
                itemBuilder: (context, index) {
                  final data = allViajes[index].data() as Map<String, dynamic>;

                  final destinoField = data['destino'];
                  final destinoFuture = obtenerDireccion(destinoField);

                  final horaFin = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;

                  

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: ListTile(
                      leading: const Icon(Icons.local_taxi, color: Colors.amber),
                      title: FutureBuilder<String>(
                        future: destinoFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Text('CARGANDO...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15));
                          }
                          final text = (snapshot.data ??
                              (destinoField is Map
                                  ? (destinoField['title']?.toString() ?? destinoField['address']?.toString() ?? 'DESTINO')
                                  : (destinoField?.toString() ?? 'DESTINO')));
                          return Text(
                            text.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          );
                        },
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Mostrar la fecha del viaje
                          if (horaFin != null)
                            Text(
                              formatoFechaHora(horaFin),
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey),
                            ),
                        ],
                      ),
                      onTap: () => mostrarDetalle(context, data),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
        
    );
  }
}
