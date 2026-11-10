import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/utils/marker_icon_helper.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/caracteristicas/disponibilidad_conductores/dominio/disponibilidad_conductores.dart';
import 'package:taxi_app/caracteristicas/disponibilidad_conductores/presentacion/tarjeta_aviso_disponibilidad.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/map_style.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/vistas/viaje_cliente_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/editar_oferta_busqueda_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel, ConductorConectado, EventoBusqueda;
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/cambiar_oferta_dialog.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/contraofertas_modal.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/moneda_format.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BuscandoTaxiView
// ─────────────────────────────────────────────────────────────────────────────

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;
  // Ubicación de recogida elegida en ConfirmarSolicitudView (widget.origen). Al
  // llegar aquí ya no hace falta esperar GPS/caché para centrar el mapa: se
  // usa directamente el punto que el cliente ya confirmó como su recogida.
  final LatLng? initialClientLocation;

  const BuscandoTaxiView({
    Key? key,
    this.solicitudId,
    this.initialClientLocation,
  }) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BuscandoTaxiViewModel _vm;
  late final AnimationController _dotsController;

  LatLng? _clientLocation;

  // Diálogo de contraofertas abierto (evita duplicarlo).
  bool _modalContraofertasAbierto = false;
  // true mientras se ejecuta el pop del modal: evita double-pop por múltiples
  // snapshots de Firestore (optimista + confirmación servidor).
  bool _dismissingModal = false;
  // Flujo de aceptación en curso: evita que la modal de ofertas se reabra.
  bool _navegandoAViaje = false;

  /// Alguien ya reclamó la salida de esta pantalla.
  ///
  /// Síncrona y sin vuelta atrás. Es lo único que garantiza que dos
  /// disparadores simultáneos —el reloj local de inactividad y el barrido
  /// server-side, que caen en el mismo minuto— no ejecuten DOS veces una
  /// navegación con `clearStackOnNext: true`. Dos de esas seguidas dejaban el
  /// Navigator con una sola ruta (o vacío) y Flutter cerraba la app.
  bool _saliendo = false;
  // Bottom sheet "Actualizar valor" abierto.
  bool _modalEditarAbierto = false;
  // Diálogo "¿Sigues buscando?" abierto (evita duplicarlo, y evita que el
  // back de Android cancele la búsqueda por debajo).
  bool _modalOfertaAbierto = false;

  // Estado UI-only: qué conductores están siendo respondidos
  final Map<String, bool> _respondingOffer = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vm = BuscandoTaxiViewModel();
    _vm.addListener(_onVmChanged);
    _vm.iniciarEscucha(
      solicitudId: widget.solicitudId,
      onAsignada: _onSolicitudAsignada,
      onTerminada: _onSolicitudTerminada,
    );

    // Esta pantalla ya avisa por su cuenta (contraofertas, conductor asignado)
    // desde los listeners del ViewModel: mientras esté montada, el handler de
    // FCM en primer plano se hace a un lado para que no salgan dos avisos del
    // mismo evento.
    final id = widget.solicitudId;
    if (id != null && id.isNotEmpty) {
      FcmService.instance.registrarPantallaDeViaje(id);
    }

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Centra de una vez con el punto de recogida ya elegido en
    // ConfirmarSolicitudView — no hay que esperar a caché/GPS para dibujar el mapa.
    _clientLocation = widget.initialClientLocation;

    _vm.startSearchTimer();
    if (widget.initialClientLocation == null) {
      // Solo si no llegó ubicación desde ConfirmarSolicitudView recurrimos a
      // caché/GPS como respaldo (compatibilidad con navegación antigua).
      _initClientLocation();
    } else {
      _maybeCalcularRuta();
    }
    // `subscribeConductores()` (conductores "disponibles") queda fuera a
    // propósito: su query lee `usuarios/{uid}.ubicacion`, un campo que no
    // escribe NADIE en todo el repo, así que solo puede devolver un mapa
    // vacío. Encima no lleva cota y se re-dispara con cada escritura de
    // cualquier conductor. Se pagaba una suscripción sin límite para no
    // obtener jamás un resultado. La posición real vive en
    // `conductores_conectados`, que es lo que sí lee
    // `subscribeConductoresConectados()`.
    _vm.subscribeConductoresConectados();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _vm.handleAppLifecycleState(state);
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeAtenderEvento();
    _maybeMostrarModalContraofertas();
    _maybeCalcularRuta();
  }

  // ── Ubicación ─────────────────────────────────────────────────────────────

  /// Dispara el cálculo de la ruta origen→destino en el ViewModel apenas se
  /// conoce la ubicación del cliente (el destino llega por Firestore, ya
  /// hidratado en el vm). Es seguro llamarla varias veces desde distintos
  /// puntos (caché, GPS fresco, snapshot de la solicitud): `calcularRuta` es
  /// idempotente y no repite la petición de red.
  void _maybeCalcularRuta() {
    final origen = _clientLocation;
    if (origen == null) return;
    _vm.calcularRuta(origen);
  }

  Future<void> _initClientLocation() async {
    // 1. Mostrar posición cacheada inmediatamente (sin esperar GPS)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('cli_last_lat');
      final lng = prefs.getDouble('cli_last_lng');
      if (lat != null && lng != null && mounted) {
        // Recentrar/encuadrar queda a cargo de
        // SearchRouteMapWidget.didUpdateWidget al recibir el nuevo
        // clientLocation — así hay un solo lugar decidiendo cuándo mover la
        // cámara.
        setState(() => _clientLocation = LatLng(lat, lng));
        _maybeCalcularRuta();
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_view');
    }

    // 2. GPS fresco en background → actualiza mapa y renueva cache
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      final fresh = LatLng(position.latitude, position.longitude);
      setState(() => _clientLocation = fresh);
      _maybeCalcularRuta();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cli_last_lat', fresh.latitude);
      await prefs.setDouble('cli_last_lng', fresh.longitude);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'buscando_taxi_view');
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  /// Reclama la salida de la pantalla. `false` si otro ya la reclamó.
  ///
  /// Todos los caminos que sacan al usuario de acá pasan por esto ANTES de su
  /// primer `await`, así que dos disparos simultáneos se resuelven sin
  /// depender de en qué orden lleguen.
  bool _reclamarSalida() {
    if (_saliendo || !mounted) return false;
    _saliendo = true;
    _vm.marcarFlujoTerminado();
    return true;
  }

  /// Cierra lo que haya encima de esta pantalla antes de navegar.
  ///
  /// Cubre los TRES modales que pueden estar arriba —"¿Sigues buscando?", la
  /// de contraofertas y `EditarOfertaBusquedaView`—, no solo el primero: con
  /// cualquiera de ellos encima, el `pushReplacement` de
  /// `navigateWithIntermediateLoader` reemplaza ESA ruta y `BuscandoTaxiView`
  /// queda viva debajo de la pantalla siguiente.
  Future<void> _cerrarModalesAbiertas() async {
    if (!mounted) return;
    final habiaModal =
        _modalOfertaAbierto ||
        _modalContraofertasAbierto ||
        _modalEditarAbierto;
    _modalOfertaAbierto = false;
    _modalContraofertasAbierto = false;
    _modalEditarAbierto = false;
    cerrarRutasSobre(context);
    if (!habiaModal) return;
    // Esperar la animación de salida antes de navegar, para que la
    // transición se vea limpia (mismo criterio que ya usaba `_aceptarOferta`).
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _onSolicitudAsignada(String solicitudId) async {
    if (!_reclamarSalida()) return;
    _navegandoAViaje = true;
    await _cerrarModalesAbiertas();
    if (!mounted) return;
    await _vm.detenerEscucha();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();
    unawaited(
      navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => ViajeClienteScreen(
          viajeId: solicitudId,
          currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
        ),
        title: 'Conductor encontrado',
        subtitle: 'Preparando tu ruta y detalles del viaje...',
      ),
    );
  }

  /// La solicitud terminó sin conductor por una vía ajena al cliente: la
  /// canceló un admin, la barrió el job server-side de solicitudes inactivas,
  /// expiró a 'sin respuesta', o el documento desapareció. Antes esto no se
  /// manejaba y el cliente quedaba girando en "Buscando conductor" para
  /// siempre. No se llama a `cancelarSolicitud()`: la solicitud ya está
  /// terminada en Firestore, solo hay que sacar al usuario de acá.
  Future<void> _onSolicitudTerminada(String estadoNormalizado) async {
    if (_navegandoAViaje || !_reclamarSalida()) return;
    await _cerrarModalesAbiertas();
    if (!mounted) return;
    await _vm.detenerEscucha();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();

    final esSinRespuesta = estadoNormalizado == SolicitudEstado.sinRespuesta;
    unawaited(
      navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const HomeClienteView(),
        title: esSinRespuesta
            ? 'Sin conductores disponibles'
            : 'Búsqueda finalizada',
        subtitle: esSinRespuesta
            ? 'Ningún conductor respondió a tu solicitud. Intenta de nuevo.'
            : 'Tu solicitud ya no está activa. Puedes pedir otro viaje.',
        icon: Icons.info_outline_rounded,
        accentColor: AppColores.warning,
        drawCheck: false,
        delay: const Duration(milliseconds: 1600),
        clearStackOnNext: true,
      ),
    );
  }

  Future<void> _cancelSolicitud() async {
    // Sin `_reclamarSalida()` este era el único camino de salida sin guard:
    // su `isCancelling` no lo levanta el autocancelado por inactividad, así
    // que el botón rojo seguía activo mientras ese corría y un tap disparaba
    // la secuencia de salida entera por segunda vez.
    if (!_reclamarSalida()) return;
    await _cerrarModalesAbiertas();
    if (!mounted) return;
    // Para el listener de Firestore antes de escribir 'cancelado': si no,
    // detecta su propia escritura y dispara `_onSolicitudTerminada` en
    // paralelo, empujando una segunda pantalla intermedia (burbuja naranja
    // de "Búsqueda finalizada") justo antes de esta.
    await _vm.detenerEscucha();
    if (!mounted) return;
    await _vm.cancelarSolicitud();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();
    unawaited(
      navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const HomeClienteView(),
        title: 'Viaje cancelado',
        subtitle: 'Has cancelado la búsqueda.',
        icon: Icons.close_rounded,
        accentColor: AppColores.error,
        drawCheck: false,
        delay: const Duration(milliseconds: 1600),
        clearStackOnNext: true,
      ),
    );
  }

  Future<void> _aceptarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true || _navegandoAViaje) return;
    _respondingOffer[conductorId] = true;
    // Marca el flujo en curso: evita que la modal se reabra mientras cierra.
    _navegandoAViaje = true;

    // 1) Cerrar primero la modal de ofertas y esperar a que termine su
    //    animación de cierre, para que la navegación se vea limpia.
    await _cerrarModalesAbiertas();
    if (!mounted) return;

    // 2) Aceptar en el backend.
    final ok = await _vm.aceptarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    if (!ok) {
      _respondingOffer.remove(conductorId);
      _navegandoAViaje = false; // permitir reintentar / reabrir modal
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo aceptar la oferta.')),
      );
      return;
    }

    // 3) Navegar al viaje con la animación de "Conductor encontrado".
    final id = widget.solicitudId;
    if (id != null) {
      await _onSolicitudAsignada(id);
    }
    // Si solicitudId es null, el listener detectará 'asignado' y navegará
    // (protegido por _navegandoAViaje para no duplicar).
  }

  Future<void> _rechazarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true) return;
    _respondingOffer[conductorId] = true;

    // Solo elimina ESA oferta. Si era la única, el modal se cierra solo cuando
    // la lista queda vacía (ver _buildModalContraofertas); si hay más, siguen
    // mostrándose. Nunca sale de buscando taxi.
    final ok = await _vm.rechazarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    _respondingOffer.remove(conductorId);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo rechazar la oferta.')),
      );
    }
  }

  // ── Modal editar valor ────────────────────────────────────────────────────

  /// Abre `EditarOfertaBusquedaView` como pantalla propia (no modal): pasa
  /// el mismo `_vm` en vivo, así que guardar ahí ya actualiza esta pantalla
  /// en tiempo real (el listener de Firestore de este State también lo
  /// confirma apenas llega el eco). Al volver, `setState` fuerza además un
  /// refresh inmediato aunque el eco de Firestore todavía no haya llegado.
  Future<void> _abrirEditarOferta() async {
    _modalEditarAbierto = true;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditarOfertaBusquedaView(vm: _vm)),
    );
    _modalEditarAbierto = false;
    if (mounted) setState(() {});
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final id = widget.solicitudId;
    if (id != null && id.isNotEmpty) {
      FcmService.instance.limpiarPantallaDeViaje(id);
    }
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final isTablet = screenW >= 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Si hay una modal/diálogo abierto, Android cierra primero esa ruta y
        // este callback NO se invoca. Aquí solo llega el back de la pantalla:
        // cancelar la búsqueda de forma limpia (sin dejar solicitud huérfana).
        if (_saliendo || _vm.flujoTerminado || _vm.isCancelling) return;
        // Si hay alguna modal abierta, no cancelar: dejar que se cierre sola.
        if (_modalEditarAbierto ||
            _modalContraofertasAbierto ||
            _modalOfertaAbierto) {
          return;
        }
        // Con "Avísame", volver no cancela: la búsqueda sigue en el inicio.
        if (_vm.avisarAlEncontrar) {
          _seguirBuscandoEnSegundoPlano();
          return;
        }
        _cancelSolicitud();
      },
      child: Scaffold(
        // El modal "Actualizar valor" tiene su propio TextField con
        // autofocus — sin esto, el Scaffold de ATRÁS (con el mapa) se
        // encogía para "evitar" el teclado que en realidad es del modal de
        // arriba, deformando el mapa mientras el teclado estaba abierto. El
        // modal ya calcula su propio padding con `viewInsets.bottom`, no
        // necesita que este Scaffold también reaccione. Mismo patrón que ya
        // usa `confirmar_solicitud_view.dart`.
        resizeToAvoidBottomInset: false,
        backgroundColor: context.palette.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 12.h),
              // Mapa: ocupa todo el espacio disponible arriba (Expanded evita
              // cualquier cálculo de altura por porcentaje de pantalla — y con
              // eso, cualquier riesgo de overflow por ese cálculo).
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 16),
                  child: _BuscandoTaxiMapa(
                    clientLocation: _clientLocation,
                    destinoLocation: _vm.destinoLocation,
                    routePoints: _vm.routePoints,
                    // `conductoresActivos` (colección
                    // `conductores_conectados`, filtrada a los últimos 5
                    // min), NO `conductoresPositions`: ese otro lee
                    // `usuarios.ubicacion`, un campo que no escribe nadie,
                    // así que llega siempre vacío.
                    conductoresConectados: _vm.conductoresActivos,
                  ),
                ),
              ),
              // Tarjeta inferior: oferta (compacta, editable), "Buscando
              // conductor", contador y botón cancelar — todo en un solo
              // bloque fijo al borde inferior.
              _buildBottomCard(isTablet, media),
            ],
          ),
        ),
      ),
    );
  }

  /// `null` hasta tener con qué calcularla: sin el primer snapshot "ninguno"
  /// no significa que no haya.
  DisponibilidadConductores? _disponibilidad() {
    final origen = _clientLocation;
    if (origen == null || !_vm.conectadosCargados) return null;
    return calcularDisponibilidad(
      _vm.conductoresActivos.map(
        (c) => ConductorPresente(
          lat: c.ubicacion.latitude,
          lng: c.ubicacion.longitude,
          esMoto: c.isMoto,
          visto: c.visto,
        ),
      ),
      lat: origen.latitude,
      lng: origen.longitude,
      ahora: DateTime.now(),
    );
  }

  /// Cambio de vehículo de un toque: el servidor reparte de nuevo a los
  /// conductores del tipo nuevo (`onSolicitudVuelveARepartir`).
  Future<void> _cambiarVehiculo(bool aMoto) async {
    final ok = await _vm.actualizarTipoVehiculo(aMoto ? 'moto' : 'carro');
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo cambiar. Intenta de nuevo.')),
    );
  }

  // ── Secciones del build ───────────────────────────────────────────────────

  /// Chip compacto de la oferta actual — tocable para editar el valor.
  /// Antes era una tarjeta grande con gradiente arriba del mapa; ahora vive
  /// dentro de la tarjeta inferior única, junto al resto del estado de
  /// búsqueda.
  Widget _buildOfertaChip(bool isTablet) {
    return InkWell(
      onTap: _vm.isUpdatingValor ? null : _abrirEditarOferta,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColores.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColores.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.local_offer_rounded,
              size: isTablet ? 20 : 18,
              color: AppColores.primary,
            ),
            SizedBox(width: 8.w),
            Text(
              'Tu oferta',
              style: TextStyle(
                fontSize: isTablet ? 13 : 12,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                '\$${formatCurrency(_vm.valorServicioActual)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14.5,
                  fontWeight: FontWeight.w800,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            if (_vm.isUpdatingValor)
              SizedBox(
                width: 16.w,
                height: 16.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColores.primary,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 14, color: AppColores.primary),
                  SizedBox(width: 4.w),
                  Text(
                    'Editar',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColores.primary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Hitos del contador de búsqueda ────────────────────────────────────────

  /// Atiende el hito que el ViewModel dejó pendiente. El evento se consume
  /// ANTES del `addPostFrameCallback`: si se consumiera después, cualquier
  /// rebuild intermedio volvería a entrar acá y dispararía el mismo hito dos
  /// veces.
  void _maybeAtenderEvento() {
    final evento = _vm.eventoPendiente;
    if (evento == null) return;
    _vm.consumirEvento();
    if (_vm.flujoTerminado || _navegandoAViaje || _saliendo) return;

    // La cancelación reclama la salida ACÁ, no dentro del post-frame: entre
    // el chequeo de arriba y el callback pasa un frame entero, y en esa
    // ventana el estado "ya estoy saliendo" quedaba sin dueño — justo el
    // frame en el que también puede llegar el snapshot terminal del barrido
    // server-side.
    if (evento == EventoBusqueda.canceladaPorInactividad &&
        !_reclamarSalida()) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (evento) {
        case EventoBusqueda.proponerCambioOferta:
          _mostrarCambiarOferta();
        case EventoBusqueda.canceladaPorInactividad:
          _cancelarPorInactividad();
      }
    });
  }

  Future<void> _mostrarCambiarOferta() async {
    // Si hay otro modal/pantalla encima no se muestra nada, y el VM se
    // reagenda solo: no arranca ningún plazo de silencio mientras el evento
    // no se haya convertido en un diálogo visible.
    if (_modalOfertaAbierto ||
        _modalContraofertasAbierto ||
        _modalEditarAbierto) {
      return;
    }
    _modalOfertaAbierto = true;
    var pidioAviso = false;
    final futuro = mostrarCambiarOfertaDialog(
      context,
      valorActual: _vm.valorServicioActual,
      validar: _vm.validarNuevoValor,
      onAvisame: () => pidioAviso = true,
    );
    // Recién con el diálogo en pantalla arranca el plazo para responder.
    _vm.registrarPropuestaMostrada();

    final nuevoValor = await futuro;
    _modalOfertaAbierto = false;
    if (!mounted) return;
    // `nuevoValor == null` también llega cuando el diálogo lo cerró el hito
    // de inactividad; ahí `flujoTerminado` ya está puesto y no hay respuesta
    // que registrar: el cliente justamente no contestó.
    if (_vm.flujoTerminado || _saliendo) return;
    // Contestar es lo único que evita la cancelación y reagenda la próxima.
    _vm.registrarRespuestaOferta();
    if (pidioAviso) {
      await _seguirBuscandoEnSegundoPlano();
      return;
    }
    if (nuevoValor == null) return;
    final ok = await _vm.actualizarValorServicio(nuevoValor);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo actualizar. Intenta de nuevo.')),
    );
  }

  /// "Avísame cuando haya un conductor": guarda el pedido y lleva al inicio,
  /// donde el banner muestra la búsqueda y abre el viaje al encontrarlo.
  ///
  /// La escritura va ANTES de reclamar la salida: si falla, el cliente sigue en
  /// esta pantalla con la búsqueda intacta.
  Future<void> _seguirBuscandoEnSegundoPlano() async {
    final ok = _vm.avisarAlEncontrar || await _vm.activarAviso();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar. Revisa tu conexión.'),
        ),
      );
      return;
    }
    if (!_reclamarSalida()) return;
    await _cerrarModalesAbiertas();
    if (!mounted) return;
    await _vm.detenerEscucha();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Seguimos buscando. Te avisaremos cuando lo encontremos.',
        ),
      ),
    );
    unawaited(
      navigator.pushNamedAndRemoveUntil(RutasApp.clienteInicio, (_) => false),
    );
  }

  /// Misma secuencia que [_cancelSolicitud] — el orden importa: parar el
  /// listener ANTES de escribir 'cancelado', o detecta su propia escritura y
  /// `_onSolicitudTerminada` empuja una segunda pantalla intermedia con el
  /// texto genérico "Búsqueda finalizada".
  Future<void> _cancelarPorInactividad() async {
    // La salida ya la reclamó `_maybeAtenderEvento` antes del post-frame.
    if (!mounted || !_saliendo) return;
    // El cliente dejó la propuesta sin contestar: cerrar el diálogo antes de
    // sacarlo de la pantalla, o queda flotando sobre la transición.
    await _cerrarModalesAbiertas();
    if (!mounted) return;
    await _vm.detenerEscucha();
    if (!mounted) return;
    final estadoReal = await _vm.marcarCanceladaPorInactividad();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();

    // No canceló: la solicitud ya no estaba en `buscando`. Si un conductor
    // aceptó en la ventana entre que este flujo reclamó la salida y la
    // transacción llegó al servidor, mandar al cliente al inicio con
    // "Búsqueda cancelada" lo deja afuera de un viaje que SÍ existe — y el
    // listener ya se detuvo, así que nada lo devolvería.
    if (estadoReal == SolicitudEstado.asignado) {
      final solicitudId = widget.solicitudId;
      if (solicitudId != null && solicitudId.isNotEmpty) {
        unawaited(
          navigateWithIntermediateLoader(
            context: context,
            nextBuilder: (_) => ViajeClienteScreen(
              viajeId: solicitudId,
              currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
            title: 'Conductor encontrado',
            subtitle: 'Preparando tu ruta y detalles del viaje...',
          ),
        );
        return;
      }
    }

    final canceloDeVerdad = estadoReal == null;
    unawaited(
      navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const HomeClienteView(),
        title: canceloDeVerdad ? 'Búsqueda cancelada' : 'Búsqueda finalizada',
        subtitle: canceloDeVerdad
            ? 'Se canceló tu solicitud automáticamente por inactividad.'
            : 'Tu solicitud ya no está activa. Puedes pedir otro viaje.',
        icon: Icons.timer_off_rounded,
        accentColor: AppColores.warning,
        drawCheck: false,
        delay: const Duration(milliseconds: 1600),
        clearStackOnNext: true,
      ),
    );
  }

  // ── Modal central de contraofertas ─────────────────────────────────────────

  void _maybeMostrarModalContraofertas() {
    if (_modalContraofertasAbierto ||
        _modalOfertaAbierto ||
        _vm.flujoTerminado ||
        _navegandoAViaje) {
      return;
    }
    if (_vm.contraofertas.isEmpty) return;
    _modalContraofertasAbierto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _modalContraofertasAbierto = false;
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _buildModalContraofertas(ctx),
      ).whenComplete(() {
        _modalContraofertasAbierto = false;
        _dismissingModal = false;
        // Re-check: new offers may have arrived while this dialog was closing.
        if (mounted && !_vm.flujoTerminado && !_navegandoAViaje) {
          _maybeMostrarModalContraofertas();
        }
      });
    });
  }

  Widget _buildModalContraofertas(BuildContext ctx) {
    return ContraofertasModalContent(
      vm: _vm,
      respondingOffer: _respondingOffer,
      onAceptar: _aceptarOferta,
      onRechazar: _rechazarOferta,
      onEmpty: _onOfertasVaciasEnModal,
    );
  }

  // Cuando ya no quedan ofertas (aceptada/rechazadas), cerrar el modal. Se usa
  // el context del State (no el del dialog) para evitar que un ctx en
  // animación de salida haga double-pop y saque BuscandoTaxiView.
  // _modalContraofertasAbierto actúa como guard de un solo disparo.
  void _onOfertasVaciasEnModal() {
    if (!mounted || !_modalContraofertasAbierto || _dismissingModal) return;
    _dismissingModal = true;
    Navigator.of(context).maybePop();
  }

  /// Tarjeta única del borde inferior: oferta compacta, "Buscando conductor"
  /// + puntos animados, contador de tiempo, y botón cancelar. Reemplaza a los
  /// tres bloques separados que antes se repartían con `Spacer`s alrededor
  /// del mapa (oferta arriba, texto+contador al medio, cancelar al fondo).
  Widget _buildBottomCard(bool isTablet, MediaQueryData media) {
    // Inset real de la barra de navegación + separación, para que el botón
    // no quede pegado a la barra de Android (gestos o 3 botones).
    final bottomPad = media.padding.bottom + 14.0;
    final disponibilidad = _disponibilidad();
    final esMoto = _vm.isMotoSolicitud;
    final tiempoEstimado = disponibilidad == null
        ? null
        : textoTiempoEstimado(
            esMoto
                ? disponibilidad.metrosMotoMasCercana
                : disponibilidad.metrosCarroMasCercano,
          );
    // Aquí solo si hay a qué cambiar: el "pocos conductores" ya se dijo antes
    // de pedir y el progreso de arriba lo cubre.
    final aviso = disponibilidad == null
        ? null
        : avisoDisponibilidad(disponibilidad, esMoto: esMoto);
    final ofertaVehiculo = aviso?.ofrecerMoto == null ? null : aviso;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 16,
        16,
        isTablet ? 32 : 16,
        bottomPad,
      ),
      decoration: BoxDecoration(
        color: context.palette.background,
        border: Border(top: BorderSide(color: context.palette.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOfertaChip(isTablet),
          SizedBox(height: 16.h),
          Text(
            'Buscando conductor',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 18 : 16,
              fontWeight: FontWeight.w800,
              color: context.palette.textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          _buildProgresoBusqueda(isTablet),
          if (tiempoEstimado != null) ...[
            SizedBox(height: 2.h),
            Text(
              'Tiempo estimado: $tiempoEstimado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: isTablet ? 13 : 12,
              ),
            ),
          ],
          SizedBox(height: 12.h),
          _buildSearchingDots(isTablet),
          SizedBox(height: 10.h),
          Text(
            _formatDuration(_vm.searchSeconds),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isTablet ? 26 : 22,
              fontWeight: FontWeight.w700,
              color: AppColores.primary,
              letterSpacing: 2,
            ),
          ),
          if (ofertaVehiculo != null) ...[
            SizedBox(height: 12.h),
            TarjetaAvisoDisponibilidad(
              aviso: ofertaVehiculo,
              onCambiarVehiculo: _vm.isUpdatingValor ? null : _cambiarVehiculo,
            ),
          ],
          SizedBox(height: 16.h),
          if (_vm.avisarAlEncontrar) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.textPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _seguirBuscandoEnSegundoPlano,
              child: const Text(
                'Volver al inicio, avísame después',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(height: 8.h),
          ],
          _buildCancelButton(isTablet),
        ],
      ),
    );
  }

  Widget _buildCancelButton(bool isTablet) {
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: ElevatedButton(
        // `_saliendo` además de `isCancelling`: el autocancelado por
        // inactividad no levanta esa bandera, así que durante su transacción
        // de Firestore el botón seguía activo y un tap ejecutaba la salida
        // por segunda vez.
        onPressed: _saliendo || _vm.isCancelling ? null : _cancelSolicitud,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColores.error,
          foregroundColor: AppColores.textWhite,
          disabledBackgroundColor: context.palette.grey400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _saliendo || _vm.isCancelling
            ? SizedBox(
                width: 18.w,
                height: 18.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColores.textWhite,
                ),
              )
            : const Text('Cancelar búsqueda'),
      ),
    );
  }

  /// Apenas un conductor ve la solicitud pasa de texto a insignia: es la señal
  /// de que la búsqueda va bien. Da un salto cada vez que sube el número.
  Widget _buildProgresoBusqueda(bool isTablet) {
    final vistas = _vm.vistasConductores;
    final texto = textoProgresoBusqueda(
      notificados: _vm.conductoresNotificados,
      vistas: vistas,
    );
    if (vistas < 1) {
      return Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.palette.textSecondary,
          fontSize: isTablet ? 14 : 12.5,
          fontWeight: FontWeight.w600,
          height: 1.3.h,
        ),
      );
    }
    return Center(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(vistas),
        tween: Tween(begin: 0.8, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        builder: (_, escala, hijo) =>
            Transform.scale(scale: escala, child: hijo),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 4.h),
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 18 : 14,
            vertical: isTablet ? 9 : 7,
          ),
          decoration: BoxDecoration(
            color: AppColores.primary,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColores.primary.withValues(alpha: 0.4),
                blurRadius: 14,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.visibility_rounded,
                size: isTablet ? 20 : 18,
                color: AppColores.ink900,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColores.ink900,
                    fontSize: isTablet ? 15 : 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingDots(bool isTablet) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final phase = (_dotsController.value + (index * 0.2)) % 1.0;
            final active = phase < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.symmetric(horizontal: 5.w),
              width: isTablet ? 12 : 10,
              height: isTablet ? 12 : 10,
              decoration: BoxDecoration(
                color: active
                    ? AppColores.buttonPrimary
                    : AppColores.buttonPrimary.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mapa de búsqueda (GoogleMap interactivo)
// ─────────────────────────────────────────────────────────────────────────────

/// Mapa en vivo de "buscando taxi": el pasajero lo mueve y acerca con gestos
/// para ver los conductores activos de la zona mientras espera.
///
/// Reemplaza a la imagen de Static Maps: con imagen no había gestos y cada
/// cambio de encuadre era una petición nueva. Sigue el patrón de
/// `MapaInteractivoPrevisualizacionSolicitud` (íconos, encuadre con
/// reintento, botón de centrar): la cámara se encuadra sola UNA vez y luego
/// no se mueve, para no pisar los gestos.
///
/// Los conductores dibujados son los del radio del reparto (3 km,
/// `repartirSolicitud`), es decir, a los que les llega la solicitud. Vienen de
/// `conductores_conectados` (ver [BuscandoTaxiViewModel.conductoresActivos]).
class _BuscandoTaxiMapa extends StatefulWidget {
  const _BuscandoTaxiMapa({
    required this.clientLocation,
    required this.destinoLocation,
    required this.routePoints,
    this.conductoresConectados = const [],
  });

  final LatLng? clientLocation;
  final LatLng? destinoLocation;
  final List<LatLng> routePoints;
  final List<ConductorConectado> conductoresConectados;

  @override
  State<_BuscandoTaxiMapa> createState() => _BuscandoTaxiMapaState();
}

class _BuscandoTaxiMapaState extends State<_BuscandoTaxiMapa> {
  static const adapter.MapService _mapService = adapter.MapService();
  static const double _paddingCamara = 64;
  static const double _zoomUnPunto = 15;

  /// Los más cercanos que entran en el primer encuadre: con un viaje corto,
  /// encuadrar solo origen y destino dejaba fuera a los conductores a 1–3 km.
  static const int _conductoresEncuadrados = 3;

  /// Tope de marcadores: en una zona densa el valor informativo se satura
  /// mucho antes.
  static const int _maxConductores = 20;

  GoogleMapController? _controller;
  BitmapDescriptor? _clienteIcon;
  BitmapDescriptor? _destinoIcon;
  BitmapDescriptor? _carroIcon;
  BitmapDescriptor? _motoIcon;

  /// El primer encuadre puede llegar antes que el primer snapshot de
  /// conductores: cuando aparecen se re-encuadra UNA vez para incluirlos.
  bool _encuadroConConductores = false;
  int _fitGen = 0;

  @override
  void initState() {
    super.initState();
    _cargarIconos();
  }

  @override
  void didUpdateWidget(covariant _BuscandoTaxiMapa oldWidget) {
    super.didUpdateWidget(oldWidget);
    final llegoDestino =
        oldWidget.destinoLocation == null && widget.destinoLocation != null;
    final llegaronConductores =
        !_encuadroConConductores && _cercanos.isNotEmpty;
    if (llegoDestino || llegaronConductores) _encuadrar();
  }

  Future<void> _cargarIconos() async {
    final r = await Future.wait([
      MarkerIconHelper.fromIcon(
        Icons.person,
        44,
        AppColores.ink900,
        borderColor: Colors.white,
        backgroundColor: AppColores.primary,
      ),
      MarkerIconHelper.fromIcon(
        Icons.flag,
        44,
        AppColores.primaryDark,
        borderColor: Colors.white,
        backgroundColor: AppColores.brand200,
      ),
      MarkerIconHelper.fromAsset(
        'assets/img/icono_carro.png',
        size: const Size(34, 34),
      ),
      MarkerIconHelper.fromAsset(
        'assets/img/icono_moto.png',
        size: const Size(34, 34),
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _clienteIcon = r[0];
      _destinoIcon = r[1];
      _carroIcon = r[2];
      _motoIcon = r[3];
    });
  }

  /// Los que reciben la solicitud: activos y dentro del radio del reparto,
  /// del más cercano al más lejano.
  List<ConductorConectado> get _cercanos {
    final cliente = widget.clientLocation;
    if (cliente == null) return const [];
    double metros(ConductorConectado c) => distanciaMetros(
      cliente.latitude,
      cliente.longitude,
      c.ubicacion.latitude,
      c.ubicacion.longitude,
    );
    final lista = [
      for (final c in widget.conductoresConectados)
        if (metros(c) <= radioBusquedaMetros) c,
    ]..sort((a, b) => metros(a).compareTo(metros(b)));
    return lista.take(_maxConductores).toList();
  }

  List<LatLng> get _puntosEncuadre => [
    ?widget.clientLocation,
    ?widget.destinoLocation,
    for (final c in _cercanos.take(_conductoresEncuadrados)) c.ubicacion,
  ];

  /// `newLatLngBounds` falla si el mapa aún no tiene su tamaño final: un
  /// reintento tras un instante alcanza (mismo patrón que la previsualización
  /// de la solicitud). [_fitGen] descarta reintentos viejos.
  Future<void> _encuadrar() async {
    final gen = ++_fitGen;
    if (await _intentarEncuadre(gen)) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (gen != _fitGen) return;
    await _intentarEncuadre(gen);
  }

  Future<bool> _intentarEncuadre(int gen) async {
    final controller = _controller;
    final puntos = _puntosEncuadre;
    if (controller == null || !mounted || puntos.isEmpty) return false;
    final conConductores = _cercanos.isNotEmpty;
    final update = puntos.length < 2
        ? _mapService.cameraToPosition(puntos.first, zoom: _zoomUnPunto)
        : _mapService.cameraToBoundsFromPoints(puntos, padding: _paddingCamara);
    if (update == null) return false;
    try {
      await controller.animateCamera(update);
    } catch (_) {
      return false;
    }
    if (gen == _fitGen && identical(_controller, controller)) {
      _encuadroConConductores = conConductores;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.clientLocation;
    final destino = widget.destinoLocation;
    final decoracion = BoxDecoration(
      color: context.palette.cardBackground,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: context.palette.borderSubtle),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
      ],
    );
    if (cliente == null) {
      return Container(
        decoration: decoracion,
        clipBehavior: Clip.antiAlias,
        child: const _MapaBusquedaCargando(),
      );
    }

    final markers = <Marker>{
      for (final (i, c) in _cercanos.indexed)
        Marker(
          markerId: MarkerId('conductor_$i'),
          position: c.ubicacion,
          anchor: const Offset(0.5, 0.5),
          // Debajo del pasajero y del destino: son contexto, no el viaje.
          zIndexInt: 0,
          icon:
              (c.isMoto ? _motoIcon : _carroIcon) ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      Marker(
        markerId: const MarkerId('cliente'),
        position: cliente,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 2,
        icon:
            _clienteIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      if (destino != null)
        Marker(
          markerId: const MarkerId('destino'),
          position: destino,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: 1,
          icon:
              _destinoIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    // El routing "engancha" la ruta al punto ruteable más cercano: se
    // agregan las coordenadas exactas para que la línea toque los íconos.
    final polylines = <Polyline>{
      if (destino != null && widget.routePoints.length >= 2)
        Polyline(
          polylineId: const PolylineId('ruta'),
          points: [cliente, ...widget.routePoints, destino],
          color: AppColores.primary,
          width: 5,
        ),
    };

    return Container(
      decoration: decoracion,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: cliente,
              zoom: _zoomUnPunto,
            ),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            style: Theme.of(context).brightness == Brightness.dark
                ? MapStyle.googleMapJson
                : null,
            markers: markers,
            polylines: polylines,
            onMapCreated: (controller) {
              _controller = controller;
              WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar());
            },
          ),
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton(
              heroTag: 'centrarMapaBusqueda',
              mini: true,
              tooltip: 'Centrar mapa',
              backgroundColor: context.palette.surface,
              foregroundColor: context.palette.textPrimary,
              onPressed: _encuadrar,
              child: const Icon(Icons.center_focus_strong),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller = null;
    super.dispose();
  }
}

/// Loader acotado al cuadro del mapa mientras no hay ubicación del cliente
/// todavía, o mientras se descarga la imagen estática ya con ubicación.
class _MapaBusquedaCargando extends StatelessWidget {
  const _MapaBusquedaCargando();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
