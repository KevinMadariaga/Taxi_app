class UsuarioModel {
  final String id;
  final String nombre;
  final String fotoUrl;
  final String fotoVehiculoUrl;
  final double? lat;
  final double? lng;

  const UsuarioModel({
    required this.id,
    required this.nombre,
    required this.fotoUrl,
    required this.fotoVehiculoUrl,
    required this.lat,
    required this.lng,
  });

  bool get hasLocation => lat != null && lng != null;

  factory UsuarioModel.empty() {
    return const UsuarioModel(
      id: '',
      nombre: '',
      fotoUrl: '',
      fotoVehiculoUrl: '',
      lat: null,
      lng: null,
    );
  }

  factory UsuarioModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return UsuarioModel.empty();

    final ubicacion = data['ubicacion'];
    double? lat;
    double? lng;

    if (ubicacion is Map<String, dynamic>) {
      lat = (ubicacion['lat'] as num?)?.toDouble();
      lng = (ubicacion['lng'] as num?)?.toDouble();
    }

    lat ??= (data['lat'] as num?)?.toDouble();
    lng ??= (data['lng'] as num?)?.toDouble();

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

    return UsuarioModel(
      id: (data['id'] ?? data['uid'] ?? '').toString(),
      nombre: (data['nombre'] ?? data['name'] ?? '').toString(),
      fotoUrl: foto.toString(),
      fotoVehiculoUrl: fotoVehiculo.toString(),
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
      'lat': lat,
      'lng': lng,
      'ubicacion': {
        'lat': lat,
        'lng': lng,
      },
    };
  }
}
