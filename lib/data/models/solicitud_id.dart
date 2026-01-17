import 'package:cloud_firestore/cloud_firestore.dart';

class SolicitudItem {
  final String id;
  final String? clienteId;
  final GeoPoint ubicacionInicial;
  GeoPoint? ubicacionDestino;
  String? metodoPago;
  String? nombreCliente;
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
    this.direccion,
    this.origenTitle,
    this.destinoTitle,
    this.distanciaKm,
  });

  factory SolicitudItem.fromMap(String id, Map<String, dynamic> map) {
    String? clienteId;
    String? nombreCliente;

    // cliente may be nested or top-level
    final cliente = map['cliente'];
    Map<String, dynamic>? clienteUbicacion;
    if (cliente is Map) {
      clienteId = cliente['id']?.toString();
      nombreCliente = cliente['nombre']?.toString();
      if (cliente['ubicacion'] is Map) {
        clienteUbicacion = Map<String, dynamic>.from(cliente['ubicacion'] as Map);
      }
    }
    clienteId ??= map['clienteId']?.toString();
    nombreCliente ??= map['clienteNombre']?.toString() ?? map['cliente_name']?.toString();

    GeoPoint ubicacionInicial;
    String? origenTitle;

    // Tomar SIEMPRE la latitud/longitud desde cliente.ubicacion
    // (nuevo esquema de ubicación del cliente).
    if (clienteUbicacion != null) {
      final lat = (clienteUbicacion['lat'] is num) ? (clienteUbicacion['lat'] as num).toDouble() : null;
      final lng = (clienteUbicacion['lng'] is num) ? (clienteUbicacion['lng'] as num).toDouble() : null;
      if (lat != null && lng != null) {
        ubicacionInicial = GeoPoint(lat, lng);
      } else {
        ubicacionInicial = const GeoPoint(0, 0);
      }
      origenTitle = (clienteUbicacion['address'] ?? clienteUbicacion['direccion'])?.toString();
    } else {
      // Si por alguna razón no viene cliente.ubicacion, usar (0,0)
      // y dejar que otras capas manejen el caso especial.
      ubicacionInicial = const GeoPoint(0, 0);
    }

    GeoPoint? ubicacionDestino;
    String? destinoTitle;
    final destino = map['destino'];
    if (destino is GeoPoint) {
      ubicacionDestino = destino;
    } else if (destino is Map) {
      final lat = (destino['lat'] is num) ? (destino['lat'] as num).toDouble() : null;
      final lng = (destino['lng'] is num) ? (destino['lng'] as num).toDouble() : null;
      if (lat != null && lng != null) ubicacionDestino = GeoPoint(lat, lng);
      destinoTitle = destino['title']?.toString() ?? destino['address']?.toString();
    }

    final metodo = map['metodo']?.toString() ?? map['metodoPago']?.toString() ?? map['metodo_pago']?.toString();

    // direccion preferimos origenTitle, luego a map['direccion']
    final direccion = origenTitle ?? map['direccion']?.toString();

    return SolicitudItem(
      id: id,
      clienteId: clienteId,
      ubicacionInicial: ubicacionInicial,
      ubicacionDestino: ubicacionDestino,
      metodoPago: metodo,
      nombreCliente: nombreCliente,
      direccion: direccion,
      origenTitle: origenTitle,
      destinoTitle: destinoTitle,
      distanciaKm: (map['distanciaKm'] is num) ? (map['distanciaKm'] as num).toDouble() : null,
    );
  }
}
