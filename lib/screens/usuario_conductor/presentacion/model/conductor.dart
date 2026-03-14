class Conductor {
  final String id;
  final String nombre;
  final String placa;
  final String foto;
  final String fotoVehiculo;
  final String correo;
  final String numero;
  final bool conectado;
  final String tipoUsuario;
  final double latitud;
  final double longitud;
  final int totalCalificaciones;
  final double calificacionPromedio;

  Conductor({
    required this.id,
    required this.nombre,
    required this.placa,
    required this.foto,
    required this.fotoVehiculo,
    required this.correo,
    required this.numero,
    required this.conectado,
    required this.tipoUsuario,
    required this.latitud,
    required this.longitud,
    required this.totalCalificaciones,
    required this.calificacionPromedio,
  });

  factory Conductor.fromMap(Map<String, dynamic> map) {
    return Conductor(
      id: map['id'] ?? '',
      nombre: map['nombre'] ?? '',
      placa: map['placa'] ?? '',
      foto: map['foto'] ?? '',
      fotoVehiculo: map['fotoVehiculo'] ?? '',
      correo: map['correo'] ?? '',
      numero: map['numero'] ?? '',
      conectado: map['conectado'] ?? false,
      tipoUsuario: map['tipoUsuario'] ?? '',
      latitud: (map['latitud'] ?? 0).toDouble(),
      longitud: (map['longitud'] ?? 0).toDouble(),
      totalCalificaciones: map['totalCalificaciones'] ?? 0,
      calificacionPromedio: (map['calificacionPromedio'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'placa': placa,
      'foto': foto,
      'fotoVehiculo': fotoVehiculo,
      'correo': correo,
      'numero': numero,
      'conectado': conectado,
      'tipoUsuario': tipoUsuario,
      'latitud': latitud,
      'longitud': longitud,
      'totalCalificaciones': totalCalificaciones,
      'calificacionPromedio': calificacionPromedio,
    };
  }
}
