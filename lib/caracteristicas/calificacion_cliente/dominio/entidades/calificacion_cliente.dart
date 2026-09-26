/// Promedio de las calificaciones que los conductores le dieron a un
/// cliente. Lo escribe solo la Cloud Function `onCalificacionRegistrada`
/// en `calificaciones_clientes/{uid}`.
class CalificacionCliente {
  const CalificacionCliente({required this.promedio, required this.total});

  final double promedio;
  final int total;

  bool get tieneCalificaciones => total > 0;
}
