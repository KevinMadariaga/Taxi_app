/// Sub-máquina de estados de la negociación de precio, dentro de una
/// solicitud. Es un dominio distinto de [SolicitudEstado]: una solicitud puede
/// estar en `buscando` con una contraoferta en `pendiente_cliente`.
///
/// Existe porque estos cuatro valores estaban escritos como literales sueltos
/// en más de veinte lugares entre cliente, conductor y Cloud Functions, sin
/// nada que garantizara que coincidieran.
///
/// El valor de cada constante ES el que ya está en Firestore: cambiarlos
/// rompería los documentos existentes y `functions/index.js`, que compara
/// contra las mismas cadenas.
///
/// Se escribe en dos campos a la vez, y ese acoplamiento es parte del
/// contrato actual del documento:
/// - `estadoContraoferta` (nivel superior) — global de la solicitud, lo pisa
///   el último conductor que oferta.
/// - `contraoferta.estado` y `contraofertas.{uid}.estado` — por oferta.
class EstadoContraoferta {
  EstadoContraoferta._();

  /// No hay negociación en curso: nadie ofertó, o ya se resolvió.
  static const String sinContraoferta = 'sin_contraoferta';

  /// Un conductor propuso otro valor y espera respuesta del cliente.
  static const String pendienteCliente = 'pendiente_cliente';

  /// El cliente aceptó la contraoferta; la solicitud pasa a `asignado`.
  static const String aceptadaCliente = 'aceptada_cliente';

  /// El cliente rechazó esa contraoferta puntual. La solicitud sigue en
  /// `buscando` y otros conductores pueden ofertar.
  static const String rechazadaCliente = 'rechazada_cliente';
}
