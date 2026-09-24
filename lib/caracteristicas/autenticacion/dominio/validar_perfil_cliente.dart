import 'package:taxi_app/core/validators/name_validator.dart';

/// Campos obligatorios de "Completa tu perfil", en el orden en que aparecen
/// en pantalla (el primero con error es al que se lleva el foco).
enum CampoPerfil { foto, nombre, apellido, telefono }

/// Valores del formulario en un instante dado.
class PerfilFormulario {
  const PerfilFormulario({
    required this.nombre,
    required this.apellido,
    required this.telefono,
    required this.tieneFoto,
  });

  final String nombre;
  final String apellido;
  final String telefono;
  final bool tieneFoto;
}

class ErrorCampo {
  const ErrorCampo(this.mensaje, {required this.vacio});

  final String mensaje;

  /// `true` si falta el dato; `false` si está pero con formato inválido.
  final bool vacio;
}

/// Deja solo los últimos 10 dígitos (quita `+57`, espacios, guiones).
String normalizarTelefono10(String? input) {
  final digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
}

/// Errores por campo; vacío si el formulario se puede enviar.
Map<CampoPerfil, ErrorCampo> validarPerfilCliente(PerfilFormulario f) {
  final errores = <CampoPerfil, ErrorCampo>{};

  if (!f.tieneFoto) {
    errores[CampoPerfil.foto] = const ErrorCampo(
      'Agrega tu foto de perfil.',
      vacio: true,
    );
  }

  final nombre = _validarNombre(f.nombre, 'nombre');
  if (nombre != null) errores[CampoPerfil.nombre] = nombre;

  final apellido = _validarNombre(f.apellido, 'apellido');
  if (apellido != null) errores[CampoPerfil.apellido] = apellido;

  final tel = normalizarTelefono10(f.telefono);
  if (tel.isEmpty) {
    errores[CampoPerfil.telefono] = const ErrorCampo(
      'Escribe tu número de celular.',
      vacio: true,
    );
  } else if (tel.length != 10) {
    final faltan = 10 - tel.length;
    errores[CampoPerfil.telefono] = ErrorCampo(
      'El celular debe tener 10 dígitos (te '
      '${faltan == 1 ? 'falta 1' : 'faltan $faltan'}).',
      vacio: false,
    );
  }

  return errores;
}

ErrorCampo? _validarNombre(String valor, String campo) {
  final v = valor.trim();
  if (v.isEmpty) return ErrorCampo('Escribe tu $campo.', vacio: true);
  if (NameValidator.validateRequired(v, fieldName: campo) != null) {
    return ErrorCampo(
      'Tu $campo solo puede tener letras y espacios.',
      vacio: false,
    );
  }
  if (v.length < 2) {
    return ErrorCampo('Tu $campo es muy corto.', vacio: false);
  }
  return null;
}

const Map<CampoPerfil, String> _nombreCampo = {
  CampoPerfil.foto: 'tu foto de perfil',
  CampoPerfil.nombre: 'tu nombre',
  CampoPerfil.apellido: 'tu apellido',
  CampoPerfil.telefono: 'tu teléfono',
};

/// Resumen para el banner: "Falta completar tu nombre y tu foto de perfil
/// para poder registrarte." `null` si no hay errores.
String? mensajeResumenPerfil(Map<CampoPerfil, ErrorCampo> errores) {
  if (errores.isEmpty) return null;
  String lista(Iterable<CampoPerfil> campos) {
    final n = campos.map((c) => _nombreCampo[c]!).toList();
    return n.length == 1
        ? n.first
        : '${n.sublist(0, n.length - 1).join(', ')} y ${n.last}';
  }

  // Orden de pantalla, no el de inserción del mapa.
  final ordenados = CampoPerfil.values.where(errores.containsKey);
  final vacios = ordenados.where((c) => errores[c]!.vacio);
  final invalidos = ordenados.where((c) => !errores[c]!.vacio);

  final partes = [
    if (vacios.isNotEmpty) 'Falta completar ${lista(vacios)}',
    if (invalidos.isNotEmpty)
      '${vacios.isEmpty ? 'Revisa' : 'revisa'} ${lista(invalidos)}',
  ];
  return '${partes.join(' y ')} para poder registrarte.';
}
