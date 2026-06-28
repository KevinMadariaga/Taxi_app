import 'package:cloud_firestore/cloud_firestore.dart';

class DriverTripParty {
  const DriverTripParty({
    required this.id,
    required this.name,
    required this.address,
    required this.photoUrl,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String address;
  final String photoUrl;
  final double? lat;
  final double? lng;

  bool get hasLocation => lat != null && lng != null;

  static String _firstText(Iterable<dynamic> candidates) {
    for (final raw in candidates) {
      if (raw == null) continue;
      final text = raw.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  factory DriverTripParty.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const DriverTripParty(
        id: '',
        name: '',
        address: '',
        photoUrl: '',
        lat: null,
        lng: null,
      );
    }

    final ubicacion = map['ubicacion'];
    double? lat;
    double? lng;
    String address = '';

    if (ubicacion is Map<String, dynamic>) {
      lat = (ubicacion['lat'] as num?)?.toDouble();
      lng = (ubicacion['lng'] as num?)?.toDouble();
      address = _firstText([
        ubicacion['direccion'],
        ubicacion['address'],
        ubicacion['texto'],
        ubicacion['title'],
        ubicacion['address_text'],
        ubicacion['formatted_address'],
        ubicacion['descripcion'],
      ]);
    } else if (ubicacion is String) {
      address = ubicacion.trim();
    }

    lat ??= (map['lat'] as num?)?.toDouble();
    lng ??= (map['lng'] as num?)?.toDouble();
    address = _firstText([
      address,
      map['direccion'],
      map['address'],
      map['direccion_recoger'],
      map['direccion_origen'],
    ]);

    final rawPhoto =
        map['foto'] ?? map['photo'] ?? map['photoUrl'] ?? map['imagen'];
    String photo = '';
    if (rawPhoto is String) {
      photo = rawPhoto;
    } else if (rawPhoto is Map<String, dynamic>) {
      photo = (rawPhoto['url'] ?? rawPhoto['link'] ?? '').toString();
    }

    return DriverTripParty(
      id: (map['id'] ?? map['uid'] ?? '').toString(),
      name: (map['nombre'] ?? map['name'] ?? '').toString(),
      address: address,
      photoUrl: photo,
      lat: lat,
      lng: lng,
    );
  }
}

class DriverTripModel {
  const DriverTripModel({
    required this.id,
    required this.status,
    required this.client,
    required this.driver,
    required this.updatedAt,
    this.destinoDireccion = '',
    this.valorServicio = 0,
    this.metodoPago = '',
    this.isMoto = false,
  });

  final String id;
  final String status;
  final DriverTripParty client;
  final DriverTripParty driver;
  final DateTime? updatedAt;
  final String destinoDireccion;
  final double valorServicio;
  final String metodoPago;
  final bool isMoto;

  factory DriverTripModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawStatus = data['estado'] ?? data['status'];
    final rawUpdated = data['updatedAt'];
    final destino = data['destino'];
    final destinoMap = destino is Map ? destino : const {};
    final tarifa = data['tarifa'];
    final tarifaMap = tarifa is Map ? tarifa : const {};

    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    return DriverTripModel(
      id: doc.id,
      status: (rawStatus ?? '').toString().toLowerCase(),
      client: DriverTripParty.fromMap(data['cliente'] as Map<String, dynamic>?),
      driver: DriverTripParty.fromMap(
        data['conductor'] as Map<String, dynamic>?,
      ),
      updatedAt: rawUpdated is Timestamp ? rawUpdated.toDate() : null,
      destinoDireccion: (data['destinoDireccion'] ??
              destinoMap['direccion'] ??
              destinoMap['title'] ??
              destinoMap['address'] ??
              '')
          .toString(),
      valorServicio: toDouble(
        tarifaMap['total'] ??
            data['valorServicio'] ??
            data['valor'] ??
            data['tarifaTotal'] ??
            data['precio'],
      ),
      metodoPago: (data['paymentMethod'] ??
              data['metodoPago'] ??
              data['metodo_pago'] ??
              '')
          .toString(),
      isMoto: (data['tipoVehiculo'] ?? data['tipo_vehiculo'] ?? '')
              .toString()
              .trim()
              .toLowerCase() ==
          'moto',
    );
  }
}
