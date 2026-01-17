import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class ResumenConductorViewModel extends ChangeNotifier {
  final String solicitudId;
  bool cargando = true;

  Map<String, dynamic>? solicitudData;
  String nombreCliente = '';
  String direccionRecogida = '';
  int duracionMinutos = 0;

  ResumenConductorViewModel({required this.solicitudId}) {
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

  String formatoDuracion(int minutos) {
    if (minutos == 0) return "0 minutos";
    if (minutos < 60) return "$minutos minutos";
    final horas = minutos ~/ 60;
    final mins = minutos % 60;
    if (mins == 0) return "$horas ${horas == 1 ? 'hora' : 'horas'}";
    return "$horas ${horas == 1 ? 'hora' : 'horas'} y $mins minutos";
  }

  Future<void> _cargar() async {
    cargando = true;
    notifyListeners();
    try {
      final solDoc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!solDoc.exists) {
        cargando = false;
        notifyListeners();
        return;
      }
      solicitudData = solDoc.data() as Map<String, dynamic>;

        // Obtener cliente (prefiere embebido en la solicitud, fallback al documento)
        final rawCliente = solicitudData!['cliente'];
        final clienteEmbebido = rawCliente is Map<String, dynamic> ? rawCliente : null;
        final clienteId = solicitudData!['clienteId'] ?? clienteEmbebido?['id'];

        nombreCliente = (clienteEmbebido?['nombre'] ?? '')
          .toString()
          .toUpperCase();

        if (nombreCliente.isEmpty && clienteId != null && clienteId.toString().isNotEmpty) {
        final clienteDoc = await FirebaseFirestore.instance
          .collection('cliente')
          .doc(clienteId)
          .get();
        nombreCliente = (clienteDoc.data()?['nombre'] ?? '')
          .toString()
          .toUpperCase();
        }

      // Calcular duración del servicio
      final fechaAceptacion = solicitudData!['fecha de aceptacion conductor'] as Timestamp?;
      final fechaTerminacion = solicitudData!['fecha de terminacion'] as Timestamp?;
      
      if (fechaAceptacion != null && fechaTerminacion != null) {
        final inicio = fechaAceptacion.toDate();
        final fin = fechaTerminacion.toDate();
        final duracion = fin.difference(inicio);
        duracionMinutos = duracion.inMinutes;
      }

      final ubicacionInicial = solicitudData!['ubicacion_inicial'];
      try {
        final placemarks = await placemarkFromCoordinates(
          ubicacionInicial.latitude,
          ubicacionInicial.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          direccionRecogida = "${p.street}, ${p.locality}, ${p.country}";
        } else {
          direccionRecogida = "Dirección no disponible";
        }
      } catch (_) {
        direccionRecogida = "Dirección no disponible";
      }
    } finally {
      cargando = false;
      notifyListeners();
    }
  }
}
