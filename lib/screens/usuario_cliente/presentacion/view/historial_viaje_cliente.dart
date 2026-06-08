import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/historial_cliente_viewmodel.dart';
import 'package:taxi_app/widgets/historial/historial_widgets.dart';

class HistorialCliente extends StatefulWidget {
  const HistorialCliente({super.key});

  @override
  HistorialClienteState createState() => HistorialClienteState();
}

class HistorialClienteState extends State<HistorialCliente> {
  final _vm = HistorialClienteViewModel();

  void _mostrarDetalle(BuildContext context, Map<String, dynamic> data) async {
    final destinoRaw = data['destino'] ?? 'Destino no disponible';
    final destino = await _vm.obtenerDireccion(destinoRaw);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (_) => DetalleViajeDialog(
        destino: destino,
        persona: _vm.extraerNombreConductor(data),
        tituloPersona: 'Conductor',
        calificacion: _vm.extraerCalificacion(data).toDouble(),
        valor: pesosFrom(_vm.extraerPrecio(data)),
        metodoPago: (data['metodoPago'] ?? 'efectivo').toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Historial de Viajes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: viajes.length,
                itemBuilder: (context, index) {
                  final data = viajes[index];
                  final destinoField = data['destino'];
                  final horaFin =
                      (data['completedAt'] ?? data['fecha de terminacion'])
                          as Timestamp?;
                  return HistorialViajeCard(
                    destinoFuture: _vm.obtenerDireccion(destinoField),
                    destinoFallback: _fallbackDestino(destinoField),
                    fecha: horaFin != null
                        ? _vm.formatoFechaHora(horaFin)
                        : null,
                    valor: pesosFrom(_vm.extraerPrecio(data)),
                    calificacion: _vm.extraerCalificacion(data).toDouble(),
                    onTap: () => _mostrarDetalle(context, data),
                  );
                },
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
