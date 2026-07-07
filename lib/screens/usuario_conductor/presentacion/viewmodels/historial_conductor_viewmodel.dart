import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

class HistorialConductorViewModel extends ChangeNotifier {
  String get conductorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<List<Map<String, dynamic>>> cargarHistorial() async {
    final uid = conductorId;
    if (uid.isEmpty) return [];
    final snap = await FirebaseFirestore.instance
        .collection('solicitudes')
        .where('conductor.id', isEqualTo: uid)
        .get();

    final completados = snap.docs.where((doc) {
      final estado = SolicitudEstado.normalize(
        (doc.data()['estado'] ?? doc.data()['status'] ?? '').toString(),
      );
      return estado == SolicitudEstado.completado;
    }).map((doc) => {'id': doc.id, ...doc.data()}).toList();

    completados.sort((a, b) {
      final aTime = (a['completedAt'] ?? a['fecha de terminacion']) as Timestamp?;
      final bTime = (b['completedAt'] ?? b['fecha de terminacion']) as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return completados;
  }

  Future<void> sincronizarCalificacion({
    required String uid,
    required double averageRating,
    required int ratingsCount,
  }) async {
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set({
            'calificacionPromedio': averageRating,
            'totalCalificaciones': ratingsCount,
            'ultimaActualizacionCalificacion': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  double extraerCalificacion(Map<String, dynamic> data) {
    final raw = data['calificacion'] ?? data['calificacion_cliente'];
    if (raw is Map) {
      final score = raw['score'] ?? raw['puntaje'] ?? raw['valor'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '') ?? 0.0;
    }
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  double extraerValorServicio(Map<String, dynamic> data) {
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

  String formatoFechaHora(Timestamp timestamp) {
    final fecha = timestamp.toDate().toUtc().subtract(const Duration(hours: 5));
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }

  String? formatarHoraFin(Map<String, dynamic> data) {
    final raw = data['completedAt'] ?? data['fecha de terminacion'];
    if (raw is Timestamp) return formatoFechaHora(raw);
    return null;
  }

  Future<String> obtenerDireccion(dynamic ubicacion) async {
    if (ubicacion is GeoPoint) {
      try {
        final placemarks = await placemarkFromCoordinates(
          ubicacion.latitude,
          ubicacion.longitude,
        );
        final p = placemarks.first;
        return '${p.street ?? ''}, ${p.locality ?? ''}';
      } catch (_) {
        return 'Dirección no disponible';
      }
    } else if (ubicacion is Map) {
      if (ubicacion['title'] != null &&
          (ubicacion['title'] as String).isNotEmpty) {
        return ubicacion['title'].toString();
      }
      final latObj = ubicacion['lat'];
      final lngObj = ubicacion['lng'];
      if (latObj != null && lngObj != null) {
        final lat = latObj is num
            ? latObj.toDouble()
            : double.tryParse(latObj.toString());
        final lng = lngObj is num
            ? lngObj.toDouble()
            : double.tryParse(lngObj.toString());
        if (lat != null && lng != null) {
          try {
            final placemarks = await placemarkFromCoordinates(lat, lng);
            final p = placemarks.first;
            return '${p.street ?? ''}, ${p.locality ?? ''}';
          } catch (_) {
            return 'Dirección no disponible';
          }
        }
      }
      return 'Destino desconocido';
    } else if (ubicacion is String) {
      return ubicacion;
    }
    return 'Origen desconocido';
  }

  String formatearDinero(double value) {
    final rounded = value.round();
    return rounded
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }
}
