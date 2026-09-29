/// Formatea una dirección para mostrarla de forma compacta: quita el sufijo
/// "Ocaña, Norte de Santander" (zona fija de operación, obvio para
/// cualquier usuario de la app) y deja como máximo los 2 segmentos más
/// relevantes de la dirección.
///
/// Única fuente de esta regla: antes vivía duplicada en
/// `MapapreviewViewModel.formatAddress` y en la resolución de dirección de
/// `crearSolicitud`.
String formatearDireccion(String? direccion) {
  if (direccion == null || direccion.trim().isEmpty) return '';

  final pattern = RegExp(
    r',?\s*Oca[nñ]a,?\s*Norte de Santander',
    caseSensitive: false,
    unicode: true,
  );
  var result = direccion.replaceAll(pattern, '');
  result = result.replaceAll(RegExp(r',\s*$'), '');
  result = result.trim();

  final parts = result
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  return parts.take(2).join(', ');
}

/// Lo que se muestra cuando un punto del mapa no tiene dirección conocida
/// (sin red, punto sin dirección catastral). Nunca se le muestran
/// coordenadas al usuario: antes cada geocodificación caía a "8.23, -73.34".
const String textoSinDireccion = 'Punto seleccionado en el mapa';

/// Plus Code de Google (ej. "7GJ3+X4" o "7GJ3+X4 Ocaña"). El geocodificador de
/// Android a veces lo devuelve como `name`/`street` de un punto sin dirección;
/// para el usuario es tan ilegible como una coordenada.
bool esPlusCode(String? texto) => RegExp(
  r'^[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{0,3}(\s|,|$)',
  caseSensitive: false,
).hasMatch((texto ?? '').trim());
