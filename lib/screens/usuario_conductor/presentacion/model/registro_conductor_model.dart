class RegistroConductorModel {
  final String id;
  final String correo;
  final String nombre;
  final String telefono;
  final String placa;
  final bool conectado;
  final String? foto;

  RegistroConductorModel({
    required this.id,
    required this.correo,
    required this.nombre,
    required this.telefono,
    required this.placa,
    this.conectado = true,
    this.foto,
  });

  factory RegistroConductorModel.fromMap(String id, Map<String, dynamic> map) {
    return RegistroConductorModel(
      id: id,
      correo: (map['correo'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      telefono: (map['telefono'] ?? '').toString(),
      placa: (map['placa'] ?? '').toString(),
      conectado: (map['conectado'] ?? true) as bool,
      foto: (map['foto'] ?? map['photo'] ?? '')?.toString().isEmpty == true ? null : (map['foto'] ?? map['photo'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'correo': correo,
      'nombre': nombre,
      'telefono': telefono,
      'placa': placa,
      'conectado': conectado,
      if (foto != null) 'foto': foto,
    };
  }
}
