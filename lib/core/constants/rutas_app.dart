/// Nombres de las rutas con nombre de la app.
///
/// Viven en `core` (y no en `routes/app_routes.dart`) para que los servicios
/// de `core` —p. ej. `FcmService` al tocar una notificación— puedan navegar
/// sin importar pantallas: `routes/` depende de las pantallas, `core` no.
class RutasApp {
  RutasApp._();

  static const String splash = '/';
  static const String login = '/login';
  static const String adminHome = '/admin-home';

  /// Args: `initialTab` (int) — 0 Reportes, 1 Mensajes, 2 Sugerencias.
  static const String adminHub = '/admin-hub';

  /// Args: `mostrarBienvenida` (bool).
  static const String conductorInicio = '/conductor/inicio';

  /// Args: `authUid` (String?), `transicionInicio` (bool) — `true` usa
  /// `transicionInicioCliente` (entrada tras login) en vez de la de Material.
  static const String clienteInicio = '/cliente/inicio';

  /// Args: `solicitudId` (String), `initialClientLocation` (LatLng?).
  static const String buscandoTaxi = '/cliente/buscando-taxi';

  /// Args: `solicitudId` (String).
  static const String resumenCliente = '/cliente/resumen';

  /// Args: `solicitudId` (String).
  static const String resumenConductor = '/conductor/resumen';

  // Pantallas de la sección "Ayuda" del cliente.
  static const String ayudaEstadoSolicitud = '/ayuda/estado-solicitud';
  static const String ayudaCambiarDestino = '/ayuda/cambiar-destino';
  static const String ayudaProblemasConductor = '/ayuda/problemas-conductor';
  static const String ayudaMetodoPago = '/ayuda/metodo-pago';
}
