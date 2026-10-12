// Enlaces de contacto de un anuncio, armados a partir de lo que escribe el
// admin (con espacios, guiones, `@` o el enlace completo).

/// `wa.me` con [numero] solo en dígitos; uno colombiano de 10 dígitos
/// (celular, empieza por 3) recibe el indicativo 57. `null` si no hay
/// número usable.
Uri? enlaceWhatsApp(String numero, {String mensaje = ''}) {
  var digitos = numero.replaceAll(RegExp(r'\D'), '');
  if (digitos.length == 10 && digitos.startsWith('3')) digitos = '57$digitos';
  if (digitos.length < 8) return null;
  return Uri.https(
    'wa.me',
    '/$digitos',
    mensaje.isEmpty ? null : {'text': mensaje},
  );
}

/// Perfil de Instagram desde `@usuario`, `usuario` o un enlace. `null` si
/// no queda un usuario válido.
Uri? enlaceInstagram(String valor) {
  var v = valor.trim();
  final enlace = RegExp(
    r'instagram\.com/([A-Za-z0-9._]+)',
    caseSensitive: false,
  ).firstMatch(v);
  if (enlace != null) v = enlace.group(1)!;
  v = v.replaceFirst(RegExp(r'^@'), '');
  if (!RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(v)) return null;
  return Uri.https('www.instagram.com', '/$v/');
}
