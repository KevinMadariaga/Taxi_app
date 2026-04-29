import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';

class HistorialClienteViewModel extends ChangeNotifier {
  HistorialClienteViewModel({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<Map<String, dynamic>>> cargarHistorial() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snap = await _firestore
        .collection('solicitudes')
        .where('cliente.id', isEqualTo: uid)
        .get();

    final docs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();

    docs.sort((a, b) {
      final aTime = (a['completedAt'] ?? a['fecha de terminacion']) as Timestamp?;
      final bTime = (b['completedAt'] ?? b['fecha de terminacion']) as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return docs;
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
      return _geocodeLatLng(ubicacion.latitude, ubicacion.longitude);
    } else if (ubicacion is Map) {
      final title = ubicacion['title'];
      if (title is String && title.isNotEmpty) return title;
      final lat = _toDouble(ubicacion['lat']);
      final lng = _toDouble(ubicacion['lng']);
      if (lat != null && lng != null) return _geocodeLatLng(lat, lng);
      return 'Destino desconocido';
    } else if (ubicacion is String) {
      return ubicacion;
    }
    return 'Origen desconocido';
  }

  Future<String> _geocodeLatLng(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      final p = placemarks.first;
      return "${p.street ?? ''}, ${p.locality ?? ''}";
    } catch (_) {
      return 'Dirección no disponible';
    }
  }

  int extraerCalificacion(Map<String, dynamic> data) {
    final obj = data['calificacion cliente'] ??
        data['calificacion'] ??
        data['calificacion_cliente'] ??
        data['rating'];
    if (obj == null) return 0;
    if (obj is Map) {
      final score = obj['score'] ?? obj['valor'] ?? obj['rating'] ?? obj['value'];
      if (score is num) return score.toInt();
      return int.tryParse(score?.toString() ?? '') ?? 0;
    }
    if (obj is num) return obj.toInt();
    return int.tryParse(obj.toString()) ?? 0;
  }

  String extraerNombreConductor(Map<String, dynamic> data) {
    final c = data['conductor'];
    if (c is Map && c['nombre'] != null) return c['nombre'].toString();
    return 'Conductor';
  }

  String extraerPrecio(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) return tarifa['total'].toString();
    if (data['valor'] != null) return data['valor'].toString();
    return '---';
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }
}
