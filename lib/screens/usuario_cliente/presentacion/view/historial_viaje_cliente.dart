import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/historial_cliente_viewmodel.dart';

class HistorialCliente extends StatefulWidget {
  const HistorialCliente({super.key});

  @override
  HistorialClienteState createState() => HistorialClienteState();
}

class HistorialClienteState extends State<HistorialCliente> {
  final _vm = HistorialClienteViewModel();

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> data) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSize = screenWidth * 0.04;

    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await _vm.obtenerDireccion(destinoRaw);
    final calificacionNum = _vm.extraerCalificacion(data);
    final conductor = _vm.extraerNombreConductor(data);
    final precio = _vm.extraerPrecio(data);
    final metodoPago =
        (data['metodoPago'] ?? 'efectivo').toString().toUpperCase();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        Icon(Icons.location_on,
                            size: 18, color: AppColores.textSecondary),
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
                    Column(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.person,
                              color: Colors.white, size: 30),
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
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.star,
                            size: 32,
                            color: index < calificacionNum
                                ? Colors.amber[600]
                                : Colors.grey[300],
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
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          "Historial de Viajes",
          style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _vm.cargarHistorial(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final viajes = snapshot.data ?? [];
          if (viajes.isEmpty) {
            return const Center(
                child: Text("No hay viajes registrados."));
          }

          return ListView.builder(
            itemCount: viajes.length,
            itemBuilder: (context, index) {
              final data = viajes[index];
              final destinoField = data['destino'];
              final destinoFuture = _vm.obtenerDireccion(destinoField);
              final horaFin = (data['completedAt'] ??
                  data['fecha de terminacion']) as Timestamp?;

              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.local_taxi,
                      color: Colors.amber),
                  title: FutureBuilder<String>(
                    future: destinoFuture,
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Text('CARGANDO...',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15));
                      }
                      final text = snap.data ??
                          (destinoField is Map
                              ? (destinoField['title']?.toString() ??
                                  destinoField['address']?.toString() ??
                                  'DESTINO')
                              : (destinoField?.toString() ?? 'DESTINO'));
                      return Text(text.toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15));
                    },
                  ),
                  subtitle: horaFin != null
                      ? Text(
                          _vm.formatoFechaHora(horaFin),
                          style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: Colors.grey),
                        )
                      : null,
                  onTap: () => _mostrarDetalle(context, data),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
