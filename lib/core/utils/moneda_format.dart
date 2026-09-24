/// Formatea un número como moneda con separador de miles ("." cada 3
/// dígitos): `7000` -> `"7.000"`.
String formatCurrency(num value) {
  final asInt = value.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < asInt.length; i++) {
    final reverseIndex = asInt.length - i;
    buf.write(asInt[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buf.write('.');
    }
  }
  return buf.toString();
}

/// Igual que [formatCurrency] pero toma el texto crudo del input (puede
/// traer separadores/caracteres no numéricos) en vez de un `num`.
String formatCurrencyFromRaw(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '0';
  final parsed = int.tryParse(digits) ?? 0;
  return formatCurrency(parsed);
}
