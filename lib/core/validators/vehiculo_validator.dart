/// Modelo y color del vehículo: los datos con los que el pasajero reconoce
/// el carro/moto que lo recoge.
class VehiculoValidator {
  VehiculoValidator._();

  static String? modelo(String? valor, {required String tipo}) {
    final v = (valor ?? '').trim();
    if (v.isEmpty) return 'Escribe la marca y el modelo de tu $tipo.';
    if (v.length < 3) {
      return 'El modelo parece incompleto (ej. Chevrolet Spark).';
    }
    return null;
  }

  static String? color(String? valor, {required String tipo}) {
    final v = (valor ?? '').trim();
    if (v.isEmpty) return 'Indica el color de tu $tipo.';
    if (!RegExp(r'^[A-Za-zÀ-ÿ\s]+$').hasMatch(v)) {
      return 'El color solo puede tener letras.';
    }
    return null;
  }

  /// "Chevrolet Spark · Blanco" (o lo que haya), para mostrar.
  static String descripcion(String? modelo, String? color) => [
    (modelo ?? '').trim(),
    (color ?? '').trim(),
  ].where((p) => p.isNotEmpty).join(' · ');
}
