/// Resultado de intentar crear una solicitud.
///
/// Antes el caso de uso devolvía un `String?` con el id tanto si acababa de
/// crear la solicitud como si el cliente ya tenía una activa. La vista no
/// podía distinguirlos, así que en el segundo caso descartaba en silencio el
/// destino, el precio, el vehículo, el método de pago y el comentario recién
/// elegidos, y navegaba a la espera de un viaje completamente distinto sin
/// ninguna explicación.
sealed class CrearSolicitudResultado {
  const CrearSolicitudResultado();
}

/// Se creó una solicitud nueva.
class SolicitudCreada extends CrearSolicitudResultado {
  const SolicitudCreada(this.solicitudId);
  final String solicitudId;
}

/// El cliente ya tenía una solicitud activa; no se creó ninguna nueva.
class SolicitudActivaExistente extends CrearSolicitudResultado {
  const SolicitudActivaExistente(this.solicitudId);
  final String solicitudId;
}

/// No se pudo completar. [motivo] es apto para mostrar al usuario.
class CrearSolicitudFallo extends CrearSolicitudResultado {
  const CrearSolicitudFallo(this.motivo);
  final String motivo;
}
