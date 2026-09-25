import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Cliente o conductor dentro de un viaje activo — datos embebidos en el
/// documento `solicitudes/{id}` (sub-mapa `cliente`/`conductor`), no un
/// perfil de cuenta independiente.
class ParticipanteViajeEntity {
  const ParticipanteViajeEntity({
    required this.id,
    required this.nombre,
    required this.fotoUrl,
    required this.fotoVehiculoUrl,
    required this.placaVehiculo,
    required this.calificacion,
    required this.totalCalificaciones,
    required this.direccion,
    required this.ubicacion,
    this.modeloVehiculo = '',
    this.colorVehiculo = '',
  });

  final String id;
  final String nombre;
  final String fotoUrl;
  final String fotoVehiculoUrl;
  final String placaVehiculo;
  final double calificacion;
  final int totalCalificaciones;
  final String direccion;
  final LatLng? ubicacion;

  /// Con qué reconoce el pasajero el vehículo, además de la placa.
  final String modeloVehiculo;
  final String colorVehiculo;

  bool get tieneUbicacion => ubicacion != null;
  bool get tieneFoto => fotoUrl.isNotEmpty;
  bool get tieneVehiculo =>
      fotoVehiculoUrl.isNotEmpty || placaVehiculo.isNotEmpty;

  static const ParticipanteViajeEntity vacio = ParticipanteViajeEntity(
    id: '',
    nombre: '',
    fotoUrl: '',
    fotoVehiculoUrl: '',
    placaVehiculo: '',
    calificacion: 0,
    totalCalificaciones: 0,
    direccion: '',
    ubicacion: null,
  );
}
