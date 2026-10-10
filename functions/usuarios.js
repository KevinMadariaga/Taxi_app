// Reglas puras sobre `usuarios/{uid}` (sin firebase-admin), para probarlas
// con `node --test`.

/** Rol declarado en el doc (`rol` o `tipoUsuario` legacy), en minúsculas. */
function rolDe(data) {
  return String((data && (data.rol || data.tipoUsuario)) || "")
    .trim()
    .toLowerCase();
}

/**
 * Registro de cliente terminado: misma regla que la app
 * (`ClientUserEntity.perfilCompleto` / `registroCompleto` del panel admin):
 * `isProfileComplete` en true Y foto.
 */
function registroCompleto(data) {
  if (!data) return false;
  const foto = String(data.foto || data.fotoUrl || "").trim();
  return data.isProfileComplete === true && foto !== "";
}

/**
 * ¿Esta escritura es la de un cliente que acaba de terminar su registro?
 *
 * El admin se entera cuando el cliente completa el perfil con foto, no
 * cuando se crea la cuenta: una cuenta a medias (solo el token FCM, o sin
 * foto) no le sirve y tampoco se lista en el panel. Un conductor que vuelve
 * a ser cliente ya tenía el registro completo: no cuenta.
 */
function esRegistroDeClienteCompletado(before, after) {
  if (!after || rolDe(after) !== "cliente") return false;
  return registroCompleto(after) && !registroCompleto(before);
}

module.exports = { rolDe, registroCompleto, esRegistroDeClienteCompletado };
