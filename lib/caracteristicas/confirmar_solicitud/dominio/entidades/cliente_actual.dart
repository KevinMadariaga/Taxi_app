/// Datos resueltos del cliente autenticado que se guardan junto a la
/// solicitud (id, nombre para mostrar al conductor, foto de perfil).
class ClienteActual {
  const ClienteActual({required this.id, required this.nombre, this.fotoUrl});

  final String id;
  final String nombre;
  final String? fotoUrl;
}
