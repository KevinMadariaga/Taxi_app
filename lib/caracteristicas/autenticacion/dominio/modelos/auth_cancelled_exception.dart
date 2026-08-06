/// El usuario abortó el inicio de sesión (cerró el selector de cuentas de
/// Google, descartó la hoja de Apple, tocó atrás).
///
/// Existe como tipo propio para poder distinguirlo de un fallo real: antes se
/// lanzaba un `StateError` con texto, la UI lo pintaba en el banner rojo y
/// Crashlytics lo registraba como error. Cancelar no es un error — no se
/// muestra nada y no se reporta.
class AuthCancelledException implements Exception {
  const AuthCancelledException([this.proveedor]);

  /// 'google' | 'apple', solo informativo para logs de depuración.
  final String? proveedor;

  @override
  String toString() =>
      'AuthCancelledException(${proveedor ?? 'desconocido'})';
}
