class ClientUserEntity {
  const ClientUserEntity({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    required this.fotoUrl,
    required this.rol,
    required this.isProfileComplete,
    required this.createdAt,
    this.email,
  });

  final String id;
  final String nombre;
  final String apellido;
  final String telefono;
  final String fotoUrl;
  final String rol;
  final String? email;
  final bool isProfileComplete;
  final DateTime createdAt;
}
