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
