class LoginConductorModel {
  final String id;
  final String correo;
  final String? nombre;

  LoginConductorModel({required this.id, required this.correo, this.nombre});

  factory LoginConductorModel.fromMap(String id, Map<String, dynamic> map) {
    return LoginConductorModel(
      id: id,
      correo: (map['correo'] ?? '').toString(),
      nombre: map['nombre']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'correo': correo, if (nombre != null) 'nombre': nombre};
  }
}
