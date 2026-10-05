/// Contacto de emergencia del usuario: nombre y teléfono por separado.
///
/// Se guarda en `usuarios/{uid}.contactosEmergencia` como lista de mapas
/// `{nombre, telefono}`. Antes era una lista de textos libres ("Mamá
/// 3001234567"); [ContactoEmergencia.desdeFirestore] sigue leyendo ese
/// formato viejo para no perder lo que ya guardaron los usuarios.
class ContactoEmergencia {
  const ContactoEmergencia({required this.nombre, required this.telefono});

  final String nombre;

  /// Solo dígitos, 10 (número colombiano, sin el +57).
  final String telefono;

  static const int digitosTelefono = 10;

  factory ContactoEmergencia.desdeFirestore(Object? raw) {
    if (raw is Map) {
      return ContactoEmergencia(
        nombre: '${raw['nombre'] ?? ''}'.trim(),
        telefono: normalizarTelefono('${raw['telefono'] ?? ''}'),
      );
    }
    // Formato viejo: un solo texto con nombre y número mezclados.
    final texto = '${raw ?? ''}'.trim();
    final telefono = normalizarTelefono(texto);
    final nombre = texto
        .replaceAll(RegExp(r'[+\d][\d\s\-().]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return ContactoEmergencia(nombre: nombre, telefono: telefono);
  }

  Map<String, String> aFirestore() => {'nombre': nombre, 'telefono': telefono};

  /// Deja solo los dígitos y quita el indicativo de Colombia (57) si viene.
  static String normalizarTelefono(String texto) {
    var digitos = texto.replaceAll(RegExp(r'\D'), '');
    if (digitos.length == digitosTelefono + 2 && digitos.startsWith('57')) {
      digitos = digitos.substring(2);
    }
    return digitos;
  }

  /// Mensaje de error del nombre, o `null` si es válido.
  static String? validarNombre(String? nombre) {
    final n = (nombre ?? '').trim();
    if (n.isEmpty) return 'Escribe el nombre';
    if (n.length < 2) return 'El nombre es muy corto';
    return null;
  }

  /// Mensaje de error del teléfono, o `null` si es válido.
  static String? validarTelefono(String? telefono) {
    final t = normalizarTelefono(telefono ?? '');
    if (t.isEmpty) return 'Escribe el número';
    if (t.length != digitosTelefono) {
      return 'Debe tener $digitosTelefono dígitos';
    }
    return null;
  }

  /// "300 123 4567" para mostrar.
  String get telefonoLegible => telefono.length == digitosTelefono
      ? '${telefono.substring(0, 3)} ${telefono.substring(3, 6)} '
            '${telefono.substring(6)}'
      : telefono;

  @override
  bool operator ==(Object other) =>
      other is ContactoEmergencia &&
      other.nombre == nombre &&
      other.telefono == telefono;

  @override
  int get hashCode => Object.hash(nombre, telefono);
}
