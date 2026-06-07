class UsuarioModel {
  final String id;
  final String nombre;
  final String fotoUrl;
  final String fotoVehiculoUrl;
  final String placaVehiculo;
  final double calificacion;
  final int totalCalificaciones;
  final String direccion;
  final double? lat;
  final double? lng;

  const UsuarioModel({
    required this.id,
    required this.nombre,
    required this.fotoUrl,
    required this.fotoVehiculoUrl,
    required this.placaVehiculo,
    required this.lat,
    required this.lng,
    this.calificacion = 0,
    this.totalCalificaciones = 0,
    this.direccion = '',
  });

  bool get hasLocation => lat != null && lng != null;

  factory UsuarioModel.empty() {
    return const UsuarioModel(
      id: '',
      nombre: '',
      fotoUrl: '',
      fotoVehiculoUrl: '',
      placaVehiculo: '',
      lat: null,
      lng: null,
    );
  }

  factory UsuarioModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return UsuarioModel.empty();

    final ubicacion = _asStringMap(data['ubicacion']);
    double? lat = _toDouble(ubicacion?['lat'] ?? ubicacion?['latitude']);
    double? lng = _toDouble(
      ubicacion?['lng'] ?? ubicacion?['longitude'] ?? ubicacion?['longitud'],
    );

    lat ??= _toDouble(data['lat'] ?? data['latitude']);
    lng ??= _toDouble(data['lng'] ?? data['longitude'] ?? data['longitud']);

    final foto =
        data['foto'] ??
        data['photo'] ??
        data['photoUrl'] ??
        data['imagen'] ??
        '';
    final fotoVehiculo =
        data['fotoVehiculo'] ??
        data['foto_carro'] ??
        data['vehiclePhotoUrl'] ??
        data['fotoAuto'] ??
        '';
    final placaVehiculo =
        data['placa'] ??
        data['placaVehiculo'] ??
        data['vehiclePlate'] ??
        data['placa_auto'] ??
        '';

    return UsuarioModel(
      id: (data['id'] ?? data['uid'] ?? data['conductorId'] ?? '').toString(),
      nombre: (data['nombre'] ?? data['name'] ?? '').toString(),
      fotoUrl: foto.toString(),
      fotoVehiculoUrl: fotoVehiculo.toString(),
      placaVehiculo: placaVehiculo.toString(),
      calificacion:
          _toDouble(
            data['calificacionPromedio'] ??
                data['calificacion'] ??
                data['rating'],
          ) ??
          0,
      totalCalificaciones:
          _toInt(
            data['totalCalificaciones'] ??
                data['totalRatings'] ??
                data['ratingCount'],
          ),
      direccion:
          (data['direccion'] ??
                  data['origenTitle'] ??
                  data['address'] ??
                  '')
              .toString(),
      lat: lat,
      lng: lng,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'foto': fotoUrl,
      'fotoVehiculo': fotoVehiculoUrl,
      'placa': placaVehiculo,
      'calificacionPromedio': calificacion,
      'totalCalificaciones': totalCalificaciones,
      'direccion': direccion,
      'lat': lat,
      'lng': lng,
      'ubicacion': {'lat': lat, 'lng': lng},
    };
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
