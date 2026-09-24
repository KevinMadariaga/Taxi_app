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

  /// Criterio único de "ya puede entrar al home": la bandera Y la foto.
  /// Cuentas viejas o editadas desde el panel admin pueden tener
  /// `isProfileComplete: true` sin foto; el cold-start
  /// (`initial_screen_resolver.dart`) ya las mandaba a completar perfil y
  /// el login interactivo no, así que el mismo usuario entraba al home o
  /// no según si reabría la app o volvía a iniciar sesión.
  bool get perfilCompleto => isProfileComplete && fotoUrl.trim().isNotEmpty;
}
