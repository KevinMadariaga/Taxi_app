import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class ResumenClienteViewModel extends ChangeNotifier {
  final String solicitudId;
  bool cargando = true;
  bool _disposed = false;

  Map<String, dynamic>? solicitudData;
  String nombreConductor = '';
  String nombreCliente = '';
  String direccionRecogida = '';
  String clienteId = '';
  String conductorId = '';
  double calificacion = 0;
  bool calificacionEnviada = false;
  String? mensajeCalificacion;
  String comentarioCalificacion = '';

  ResumenClienteViewModel({required this.solicitudId}) {
    _cargar();
  }

  String formatoHoraBogota(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    final fechaUtc = timestamp.toDate().toUtc();
    final fecha = fechaUtc.subtract(const Duration(hours: 5)); // UTC-5 Bogotá
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    final anio = fecha.year;
    int h24 = fecha.hour;
    final amPm = h24 >= 12 ? 'PM' : 'AM';
    int h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final hora = h12.toString().padLeft(2, '0');
    final minuto = fecha.minute.toString().padLeft(2, '0');
    return "$dia/$mes/$anio $hora:$minuto $amPm";
  }

  void setCalificacion(double valor) {
    calificacion = valor;
    if (!_disposed) notifyListeners();
  }

  void setComentarioCalificacion(String valor) {
    comentarioCalificacion = valor;
    if (!_disposed) notifyListeners();
  }

  Future<void> enviarCalificacion() async {
    if (calificacion == 0) {
      mensajeCalificacion = 'Por favor selecciona una calificación';
      if (!_disposed) notifyListeners();
      return;
    }

    try {
      final data = solicitudData ?? {};
      final conductorData = data['conductor'] as Map<String, dynamic>?;
      final conductorIdLocal = (conductorData?['id'] as String?) ?? conductorId;

      // Guardar calificación dentro del documento de la solicitud
      await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .update({
            'calificacion_cliente': {
              'score': calificacion,
              'comment': comentarioCalificacion.isNotEmpty ? comentarioCalificacion : null,
              'ratedAt': Timestamp.now(),
            },
          });

      // Calcular y actualizar promedio de calificación del conductor consultando
      // la colección `solicitudes` (donde ahora se guardan las calificaciones).
      if (conductorIdLocal != null && conductorIdLocal.isNotEmpty) {
        try {
          final viajesSnapshot = await FirebaseFirestore.instance
              .collection('solicitudes')
              .where('conductor.id', isEqualTo: conductorIdLocal)
              .get();

          double totalCalificacion = 0.0;
          int cantidadCalificaciones = 0;

          for (var doc in viajesSnapshot.docs) {
            final viajeData = doc.data();
            final calificacionObj = viajeData['calificacion_cliente'];
            if (calificacionObj is Map && calificacionObj['score'] != null) {
              totalCalificacion += (calificacionObj['score'] as num).toDouble();
              cantidadCalificaciones++;
            }
          }

          if (cantidadCalificaciones > 0) {
            final promedioCalificacion = totalCalificacion / cantidadCalificaciones;

            // Actualizar calificación promedio en el documento del conductor
            await FirebaseFirestore.instance
                .collection('usuario_conductor')
                .doc(conductorIdLocal)
                .update({
                  'calificacion_promedio': promedioCalificacion,
                  'total_calificaciones': cantidadCalificaciones,
                  'ultima_actualizacion_calificacion': FieldValue.serverTimestamp(),
                });
          }
        } catch (e) {
          // Error al actualizar promedio, pero la calificación ya se guardó
          debugPrint('Error al actualizar promedio del conductor: $e');
        }
      }

      calificacionEnviada = true;
      mensajeCalificacion = '¡Calificación guardada exitosamente!';
      if (!_disposed) notifyListeners();
    } catch (e) {
      mensajeCalificacion = 'Error al guardar calificación: ${e.toString()}';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _cargar() async {
    cargando = true;
    if (!_disposed) notifyListeners();
    try {
      final solDoc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!solDoc.exists) {
        cargando = false;
        if (!_disposed) notifyListeners();
        return;
      }
      solicitudData = solDoc.data() as Map<String, dynamic>;

      // Obtener IDs desde la solicitud (usa los embebidos si existen)
      final rawConductor = solicitudData!['conductor'];
      final conductorEmbebido =
        rawConductor is Map<String, dynamic> ? rawConductor : null;
      clienteId = solicitudData!['clienteId'] ?? '';
      conductorId = solicitudData!['conductorId'] ?? conductorEmbebido?['id'] ?? '';

      // Obtener nombre y ubicación del cliente desde la solicitud
      final clienteRaw = solicitudData!['cliente'];
      if (clienteRaw is Map<String, dynamic>) {
        clienteId = clienteRaw['id'] ?? clienteId;
        nombreCliente = (clienteRaw['nombre'] ?? '').toString().toUpperCase();
        
        // Obtener ubicación del cliente (origen)
        final ubicacionClienteRaw = clienteRaw['ubicacion'];
        if (ubicacionClienteRaw is Map<String, dynamic>) {
          direccionRecogida = ubicacionClienteRaw['address']?.toString() ?? 'Dirección no disponible';
        }
      }

      // Verificar si ya existe calificación
      if (solicitudData!.containsKey('calificacion cliente')) {
        calificacion = (solicitudData!['calificacion cliente'] ?? 0).toDouble();
        calificacionEnviada = true;
      }

      // Obtener nombre del conductor: primero desde el objeto embebido en la solicitud, luego fallback al documento
      nombreConductor = (conductorEmbebido?['nombre'] ?? '')
          .toString()
          .toUpperCase();
      if (nombreConductor.isEmpty && conductorId.isNotEmpty) {
        final conductorDoc = await FirebaseFirestore.instance
            .collection('usuario_conductor')
            .doc(conductorId)
            .get();
        nombreConductor = (conductorDoc.data()?['nombre'] ?? '')
            .toString()
            .toUpperCase();
      }

      // Si no se obtuvo ubicación desde el cliente, intentar obtenerla de ubicacion_inicial
      if (direccionRecogida == 'Dirección no disponible') {
        final ubicacionInicial = solicitudData!['ubicacion_inicial'];
        try {
          final placemarks = await placemarkFromCoordinates(
            ubicacionInicial.latitude,
            ubicacionInicial.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            direccionRecogida = "${p.street}, ${p.locality}, ${p.country}";
          }
        } catch (_) {
          direccionRecogida = "Dirección no disponible";
        }
      }
    } finally {
      cargando = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
