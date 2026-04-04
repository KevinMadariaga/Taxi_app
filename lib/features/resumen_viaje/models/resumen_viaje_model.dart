import 'package:cloud_firestore/cloud_firestore.dart';

class ResumenViajeModel {
  const ResumenViajeModel({
    required this.solicitudId,
    required this.clienteNombre,
    required this.conductorNombre,
    required this.destinoDireccion,
    required this.valorServicio,
    required this.fechaViaje,
    required this.calificacion,
    required this.comentarioCalificacion,
  });

  final String solicitudId;
  final String clienteNombre;
  final String conductorNombre;
  final String destinoDireccion;
  final double valorServicio;
  final DateTime? fechaViaje;
  final double? calificacion;
  final String comentarioCalificacion;

  factory ResumenViajeModel.fromFirestore({
    required String solicitudId,
    required Map<String, dynamic> data,
  }) {
    final clienteMap = _asMap(data['cliente']);
    final conductorMap = _asMap(data['conductor']);
    final destinoMap = _asMap(data['destino']);

    final clienteNombre = _firstString([
      data['clienteNombre'],
      clienteMap?['nombre'],
      clienteMap?['name'],
      data['nombre_cliente'],
    ], fallback: 'Cliente');

    final conductorNombre = _firstString([
      data['conductorNombre'],
      conductorMap?['nombre'],
      conductorMap?['name'],
      data['nombre_conductor'],
    ], fallback: 'Conductor');

    final destinoDireccion = _firstString([
      data['destinoDireccion'],
      destinoMap?['direccion'],
      destinoMap?['address'],
      destinoMap?['title'],
      data['direccion_seleccionada'],
    ], fallback: 'No disponible');

    final tarifaMap = _asMap(data['tarifa']);
    final valorServicio = _toDouble(
      tarifaMap?['total'] ??
          data['tarifaTotal'] ??
          data['valorServicio'] ??
          data['valor'] ??
          data['precio'],
    );

    final fechaViaje = _toDateTime(
      data['fechaViaje'] ?? data['fecha de terminacion'],
    );

    final calificacion = _toNullableDouble(data['calificacion']);
    final comentarioCalificacion = (data['comentarioCalificacion'] ?? '')
        .toString()
        .trim();

    return ResumenViajeModel(
      solicitudId: solicitudId,
      clienteNombre: clienteNombre,
      conductorNombre: conductorNombre,
      destinoDireccion: destinoDireccion,
      valorServicio: valorServicio,
      fechaViaje: fechaViaje,
      calificacion: calificacion,
      comentarioCalificacion: comentarioCalificacion,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  static String _firstString(
    List<dynamic> candidates, {
    required String fallback,
  }) {
    for (final item in candidates) {
      final text = item?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return fallback;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      final ms = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
