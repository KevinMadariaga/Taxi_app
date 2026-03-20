import 'package:cloud_firestore/cloud_firestore.dart';

class SolicitudItem {
  final String id;
  final String? clienteId;
  final GeoPoint ubicacionInicial;
  GeoPoint? ubicacionDestino;
  String? metodoPago;
  String? nombreCliente;
  String? comentarioCliente;
  String? direccion; // origin title/address
  String? origenTitle;
  String? destinoTitle;
  double? distanciaKm;

  SolicitudItem({
    required this.id,
    required this.clienteId,
    required this.ubicacionInicial,
    this.ubicacionDestino,
    this.metodoPago,
    this.nombreCliente,
    this.comentarioCliente,
    this.direccion,
    this.origenTitle,
    this.destinoTitle,
    this.distanciaKm,
  });

  factory SolicitudItem.fromMap(String id, Map<String, dynamic> map) {
    final cliente = _asMap(map['cliente']);
    final clienteUbicacion = _asMap(cliente?['ubicacion']);
    final origen = _asMap(map['origen']);
    final destino = _asMap(map['destino']);

    String? clienteId = _firstText([
      cliente?['id'],
      cliente?['uid'],
      cliente?['clienteId'],
      map['clienteId'],
    ]);

    String? nombreCliente = _firstText([
      cliente?['nombre'],
      cliente?['name'],
      map['clienteNombre'],
      map['cliente_name'],
      map['nombre_cliente'],
    ]);

    GeoPoint ubicacionInicial =
        _toGeoPoint(clienteUbicacion) ??
        (map['ubicacion_inicial'] is GeoPoint
            ? map['ubicacion_inicial'] as GeoPoint
            : null) ??
        _toGeoPoint(origen) ??
        const GeoPoint(0, 0);

    final origenTitle = _firstText([
      origen?['title'],
      origen?['address'],
      origen?['direccion'],
      origen?['address_text'],
      clienteUbicacion?['address'],
      clienteUbicacion?['direccion'],
      map['direccion'],
      map['direccion_recoger'],
      map['direccion_origen'],
      map['ubicacion_text'],
    ]);

    GeoPoint? ubicacionDestino;
    String? destinoTitle;
    final destinoRaw = map['destino'];
    if (destinoRaw is GeoPoint) {
      ubicacionDestino = destinoRaw;
    } else {
      ubicacionDestino = _toGeoPoint(destino);
      destinoTitle = _firstText([
        destino?['title'],
        destino?['address'],
        destino?['direccion'],
      ]);
    }

    final metodo = _firstText([
      map['metodo'],
      map['metodoPago'],
      map['metodo_pago'],
    ]);

    final calificacion = _asMap(map['calificacion']);

    final comentarioCliente = _firstCommentText([
      map['comentario'],
      map['comentarioCliente'],
      map['comentario_cliente'],
      map['comentarioCalificacion'],
      calificacion?['comentario'],
      calificacion?['comentarioCalificacion'],
      calificacion?['comentario_cliente'],
      cliente?['comentario'],
      cliente?['comentarioCalificacion'],
    ]);

    final direccion = origenTitle;

    return SolicitudItem(
      id: id,
      clienteId: clienteId,
      ubicacionInicial: ubicacionInicial,
      ubicacionDestino: ubicacionDestino,
      metodoPago: metodo,
      nombreCliente: nombreCliente,
      comentarioCliente: comentarioCliente,
      direccion: direccion,
      origenTitle: origenTitle,
      destinoTitle: destinoTitle,
      distanciaKm: (map['distanciaKm'] is num)
          ? (map['distanciaKm'] as num).toDouble()
          : null,
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String? _firstCommentText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) continue;

      final lower = text.toLowerCase();
      if (lower == 'null' ||
          lower == 'sin comentario' ||
          lower == 'ninguno' ||
          lower == 'n/a' ||
          lower == 'na' ||
          text == '-') {
        continue;
      }

      return text;
    }
    return null;
  }

  static GeoPoint? _toGeoPoint(Map<String, dynamic>? value) {
    if (value == null) return null;
    final lat = _toDouble(value['lat'] ?? value['latitude']);
    final lng = _toDouble(
      value['lng'] ?? value['longitude'] ?? value['longitud'],
    );
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
