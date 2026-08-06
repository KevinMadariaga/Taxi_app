import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/app_remote_config_service.dart';
import 'package:taxi_app/core/services/map_service_adapter.dart' as adapter;
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/vistas/viaje_cliente_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/editar_oferta_busqueda_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel;
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/contraofertas_modal.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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
  // Navegación al viaje ya realizada: evita duplicarla (manual + listener).
  bool _viajeNavegado = false;
  // Bottom sheet "Actualizar valor" abierto.
  bool _modalEditarAbierto = false;

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

  Future<void> _onSolicitudAsignada(String solicitudId) async {
    if (!mounted || _viajeNavegado) return;
    _viajeNavegado = true;
    _navegandoAViaje = true;
    _vm.marcarFlujoTerminado();
    await _vm.detenerEscucha();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();
    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => ViajeClienteScreen(
        viajeId: solicitudId,
        currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
      title: 'Conductor encontrado',
      subtitle: 'Preparando tu ruta y detalles del viaje...',
    );
  }

  /// La solicitud terminó sin conductor por una vía ajena al cliente: la
  /// canceló un admin, la barrió el job server-side de solicitudes inactivas,
  /// expiró a 'sin respuesta', o el documento desapareció. Antes esto no se
  /// manejaba y el cliente quedaba girando en "Buscando conductor" para
  /// siempre. No se llama a `cancelarSolicitud()`: la solicitud ya está
  /// terminada en Firestore, solo hay que sacar al usuario de acá.
  Future<void> _onSolicitudTerminada(String estadoNormalizado) async {
    if (!mounted || _viajeNavegado || _navegandoAViaje) return;
    _viajeNavegado = true;
    _vm.marcarFlujoTerminado();
    await _vm.detenerEscucha();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();

    final esSinRespuesta = estadoNormalizado == SolicitudEstado.sinRespuesta;
    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => const HomeClienteView(),
      title: esSinRespuesta ? 'Sin conductores disponibles' : 'Búsqueda finalizada',
      subtitle: esSinRespuesta
          ? 'Ningún conductor respondió a tu solicitud. Intenta de nuevo.'
          : 'Tu solicitud ya no está activa. Puedes pedir otro viaje.',
      icon: Icons.info_outline_rounded,
      accentColor: AppColores.warning,
      drawCheck: false,
      delay: const Duration(milliseconds: 1600),
      clearStackOnNext: true,
    );
  }

  Future<void> _cancelSolicitud() async {
    if (_vm.isCancelling) return;
    _vm.marcarFlujoTerminado();
    await _vm.cancelarSolicitud();
    if (!mounted) return;
    _vm.finalizarTrackingConductores();
    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => const HomeClienteView(),
      title: 'Viaje cancelado',
      subtitle: 'Has cancelado la búsqueda.',
      icon: Icons.close_rounded,
      accentColor: AppColores.error,
      drawCheck: false,
      delay: const Duration(milliseconds: 1600),
      clearStackOnNext: true,
    );
  }

  Future<void> _aceptarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true || _navegandoAViaje) return;
    _respondingOffer[conductorId] = true;
    // Marca el flujo en curso: evita que la modal se reabra mientras cierra.
    _navegandoAViaje = true;

    // 1) Cerrar primero la modal de ofertas y esperar a que termine su
    //    animación de cierre, para que la navegación se vea limpia.
    if (_modalContraofertasAbierto && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      _modalContraofertasAbierto = false;
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
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

  String _formatCurrency(num value) {
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
        if (_vm.flujoTerminado || _vm.isCancelling) return;
        // Si hay alguna modal abierta, no cancelar: dejar que se cierre sola.
        if (_modalEditarAbierto || _modalContraofertasAbierto) return;
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
        backgroundColor: AppColores.background,
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
                  child: _BuscandoTaxiStaticMap(
                    clientLocation: _clientLocation,
                    destinoLocation: _vm.destinoLocation,
                    routePoints: _vm.routePoints,
                    isMoto: _vm.isMotoSolicitud,
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
                color: AppColores.textSecondary,
              ),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                '\$${_formatCurrency(_vm.valorServicioActual)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
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

  // ── Modal central de contraofertas ─────────────────────────────────────────

  void _maybeMostrarModalContraofertas() {
    if (_modalContraofertasAbierto || _vm.flujoTerminado || _navegandoAViaje)
      return;
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 16,
        16,
        isTablet ? 32 : 16,
        bottomPad,
      ),
      decoration: const BoxDecoration(
        color: AppColores.background,
        border: Border(top: BorderSide(color: AppColores.borderSubtle)),
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
              color: AppColores.textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Buscamos al conductor más cercano para ti.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColores.textSecondary,
              fontSize: isTablet ? 14 : 12.5,
              fontWeight: FontWeight.w600,
              height: 1.3.h,
            ),
          ),
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
          SizedBox(height: 16.h),
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
        onPressed: _vm.isCancelling ? null : _cancelSolicitud,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColores.error,
          foregroundColor: AppColores.textWhite,
          disabledBackgroundColor: AppColores.grey400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          textStyle: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _vm.isCancelling
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
// Mapa estático de búsqueda (Static Maps API)
// ─────────────────────────────────────────────────────────────────────────────

/// Mapa de la pantalla "buscando taxi" construido con una imagen estática de
/// Google Static Maps API en vez de un `GoogleMap` embebido: un mapa en vivo
/// gasta GPU/RAM en tiles renderizados solo para mostrar dos puntos fijos
/// (origen y destino) que no se mueven mientras se busca conductor — mismo
/// criterio ya aplicado en `_HomeClienteMap`/`_HomeConductorIdleMap`.
///
/// Reemplaza a `SearchRouteMapWidget` (que queda huérfano/sin caller, no se
/// borró por si se necesita como referencia). Decisiones tomadas acá:
///
/// - **Encuadre**: se calcula el bounding box de origen+destino y se deriva
///   un zoom continuo (fórmula estándar `getBoundsZoomLevel` de Google, misma
///   familia de proyección Mercator que usa `_boundsZoom` abajo) para que
///   ambos puntos quepan
///   con margen — sin escalones fijos ni zoom constante: sigue funcionando
///   igual de bien cerca que lejos.
/// - **Marcador del cliente**: Static Maps no puede dibujar un ícono que es
///   un asset local de Flutter (necesitaría URL pública), así que se
///   proyecta la coordenada a un offset en píxeles respecto al centro de la
///   imagen (misma familia de fórmula que el zoom) y se overlay-ea con
///   `Positioned` el ícono real de carro/moto según `isMoto` (mismos assets
///   que ya usaba `SearchRouteMapWidget`).
/// - **Marcador de destino**: se overlay-ea con el mismo mecanismo (en vez
///   del parámetro nativo `markers=` de Static Maps) para poder usar el pin
///   de marca (`map_pin_red.png`, el mismo asset que el resto de la app) en
///   vez del pin genérico de Google — el offset de proyección ya hacía
///   falta para el ícono del cliente, así que reusarlo acá no cuesta
///   matemática adicional.
/// - **Ruta**: se dibuja también sobre la imagen vía `path=enc:<polyline>`,
///   codificando `routePoints` (ya resuelto por calles en el ViewModel) con
///   el algoritmo estándar de Google Polyline (`MapService.encodePolyline`,
///   inverso de `decodePolyline`).
/// - **Conductores cercanos/conectados**: a propósito NO se dibujan en este
///   mapa — el pedido explícito fue solo los dos marcadores (cliente +
///   destino). Las suscripciones de Firestore que alimentan esos datos en
///   el ViewModel (`subscribeConductores`/`subscribeConductoresConectados`)
///   siguen intactas; solo se dejó de visualizarlos acá.
class _BuscandoTaxiStaticMap extends StatelessWidget {
  const _BuscandoTaxiStaticMap({
    required this.clientLocation,
    required this.destinoLocation,
    required this.routePoints,
    required this.isMoto,
  });

  final LatLng? clientLocation;
  final LatLng? destinoLocation;
  final List<LatLng> routePoints;
  final bool isMoto;

  static const adapter.MapService _mapService = adapter.MapService();

  // Zoom fijo mientras solo se conoce el cliente (destino aún hidratándose
  // desde Firestore) — mismo valor que usan los mapas estáticos de los home.
  static const double _zoomSinDestino = 16;
  static const double _zoomMin = 3;
  static const double _zoomMax = 20;

  static const double _vehicleIconSize = 40;
  static const double _destinoIconSize = 44;

  // ── Proyección Web Mercator (mismas fórmulas que usa Google Maps/Static
  // Maps internamente para pasar de lat/lng a píxeles) ───────────────────

  static Offset _project(LatLng point) {
    final double sinLat = math
        .sin(point.latitude * math.pi / 180)
        .clamp(-0.9999, 0.9999)
        .toDouble();
    final double x = 128.0 + point.longitude * (256.0 / 360.0);
    final double y =
        128.0 -
        (math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi)) * 256.0;
    return Offset(x, y);
  }

  /// Offset en píxeles (respecto a [center]) de [point], al [zoom] dado.
  /// Misma unidad de píxeles que el parámetro `size` de Static Maps: el
  /// `scale=2` de retina no afecta esta cuenta, solo aumenta la densidad de
  /// la imagen, no el área geográfica que cubre.
  static Offset _pixelOffset({
    required LatLng center,
    required LatLng point,
    required double zoom,
  }) {
    final double scale = math.pow(2, zoom).toDouble();
    final Offset centerPx = _project(center);
    final Offset pointPx = _project(point);
    return Offset(
      (pointPx.dx - centerPx.dx) * scale,
      (pointPx.dy - centerPx.dy) * scale,
    );
  }

  static double _latRad(double lat) {
    final double sinLat = math
        .sin(lat * math.pi / 180)
        .clamp(-0.9999, 0.9999)
        .toDouble();
    final double radX2 = math.log((1.0 + sinLat) / (1.0 - sinLat)) / 2.0;
    return radX2.clamp(-math.pi, math.pi) / 2.0;
  }

  /// Zoom continuo que encuadra el bounding box de [a] y [b] dentro de un
  /// viewport de [widthPx]x[heightPx] (fórmula estándar `getBoundsZoomLevel`
  /// de Google): el zoom sigue bajando de forma continua a medida que crece
  /// la distancia entre los puntos, sin techo/piso a mitad de escala.
  static double _boundsZoom(
    LatLng a,
    LatLng b,
    double widthPx,
    double heightPx,
  ) {
    const double worldDim = 256.0;
    // Margen para que los íconos (que tienen alto/ancho propio, no son
    // puntos infinitesimales) no queden pegados al borde de la imagen.
    final double effectiveWidth = math.max(40.0, widthPx - 90.0);
    final double effectiveHeight = math.max(40.0, heightPx - 120.0);

    final LatLng sw = LatLng(
      math.min(a.latitude, b.latitude),
      math.min(a.longitude, b.longitude),
    );
    final LatLng ne = LatLng(
      math.max(a.latitude, b.latitude),
      math.max(a.longitude, b.longitude),
    );

    final double latFraction =
        (_latRad(ne.latitude) - _latRad(sw.latitude)) / math.pi;
    final double lngDiff = ne.longitude - sw.longitude;
    final double lngFraction =
        (lngDiff < 0 ? lngDiff + 360.0 : lngDiff) / 360.0;

    double zoomFor(double mapPx, double fraction) {
      if (fraction <= 0) return _zoomMax;
      return math.log(mapPx / worldDim / fraction) / math.ln2;
    }

    final double latZoom = zoomFor(effectiveHeight, latFraction.abs());
    final double lngZoom = zoomFor(effectiveWidth, lngFraction.abs());

    return math.min(latZoom, lngZoom).clamp(_zoomMin, _zoomMax).toDouble();
  }

  String _staticMapUrl({
    required LatLng center,
    required double zoom,
    required int width,
    required int height,
    required String apiKey,
    String? encodedPath,
  }) {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/staticmap', {
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom.floor().toString(),
      'size': '${width}x$height',
      'scale': '2',
      'maptype': 'roadmap',
      'key': apiKey,
      // Static Maps espera RRGGBBAA (hex, sin '#', alpha al final) — se
      // arma desde `AppColores.primary` (naranja de marca) en vez de un
      // hex suelto para no volver a desincronizarse si el color cambia.
      // Un solo `path=` (sin doble trazo): para una ruta corta de búsqueda
      // no hace falta la técnica de doble polyline que sí usa el mapa de
      // tracking en vivo.
      if (encodedPath != null)
        'path': 'color:0x${_routePathHex()}|weight:5|enc:$encodedPath',
    });
    return uri.toString();
  }

  /// `RRGGBBAA` (Static Maps) desde `AppColores.primary` con ~80% opacidad
  /// — el `Color` de Flutter guarda alpha primero (`AARRGGBB`).
  String _routePathHex() {
    final rgb = (AppColores.primary.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return '${rgb}CC';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final client = clientLocation;
          if (client == null) {
            return const _MapaBusquedaCargando();
          }

          // Static Maps API acepta como máximo 640x640 en "size" (antes de
          // aplicar "scale") — mismo límite que ya respetan los mapas
          // estáticos de los home de cliente/conductor.
          final double width = constraints.maxWidth
              .clamp(100.0, 640.0)
              .toDouble();
          final double height = constraints.maxHeight
              .clamp(100.0, 640.0)
              .toDouble();

          final destino = destinoLocation;
          final bool hasDestino = destino != null;
          final LatLng center = hasDestino
              ? LatLng(
                  (client.latitude + destino.latitude) / 2,
                  (client.longitude + destino.longitude) / 2,
                )
              : client;
          // Redondeado ACÁ, una sola vez: Static Maps solo acepta zoom
          // entero, así que la imagen real siempre se renderiza al valor
          // truncado. Si los offsets de los íconos se calculan con el zoom
          // sin truncar (ej. 14.9) mientras la imagen se pidió a 14, la
          // matemática de posición asume una imagen más acercada de la que
          // realmente llegó — los íconos terminan empujados fuera del
          // cuadro. Truncar antes de derivar todo lo demás mantiene la
          // imagen pedida y los offsets consistentes entre sí.
          final double zoom =
              (hasDestino
                      ? _boundsZoom(client, destino, width, height)
                      : _zoomSinDestino)
                  .floorToDouble();

          // El routing (OSRM/Directions) "engancha" la ruta al punto
          // ruteable más cercano, que casi nunca es exactamente la
          // coordenada del cliente/destino — sin esto, la línea quedaba
          // flotando a un tramo del ícono de vehículo y del pin en vez de
          // salir/llegar justo desde/hacia ellos. Se antepone/agrega la
          // coordenada exacta como primer/último punto para que la traza
          // siempre toque los dos íconos.
          final String? encodedPath = (hasDestino && routePoints.length >= 2)
              ? _mapService.encodePolyline([client, ...routePoints, destino])
              : null;

          return FutureBuilder<String>(
            future: AppRemoteConfigService.instance.fetchStaticMapsApiKey(),
            builder: (context, keySnapshot) {
              if (keySnapshot.connectionState != ConnectionState.done) {
                return const _MapaBusquedaCargando();
              }
              final apiKey = keySnapshot.data ?? '';
              if (apiKey.isEmpty) {
                return const _MapaBusquedaPlaceholder();
              }

              final url = _staticMapUrl(
                center: center,
                zoom: zoom,
                width: width.round(),
                height: height.round(),
                apiKey: apiKey,
                encodedPath: encodedPath,
              );

              return Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    key: ValueKey(url),
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, _) => const _MapaBusquedaCargando(),
                    errorWidget: (context, _, error) {
                      ErrorReporter.report(
                        error,
                        StackTrace.current,
                        reason:
                            'buscando_taxi_view: falló imagen de Static Maps',
                      );
                      return const _MapaBusquedaPlaceholder();
                    },
                  ),
                  if (hasDestino)
                    _MapPinOverlay(
                      offset: _pixelOffset(
                        center: center,
                        point: destino,
                        zoom: zoom,
                      ),
                      boxWidth: width,
                      boxHeight: height,
                      iconSize: _destinoIconSize,
                      child: Image.asset(
                        'assets/img/map_pin_red.png',
                        width: _destinoIconSize,
                        height: _destinoIconSize,
                      ),
                    ),
                  _MapPinOverlay(
                    offset: hasDestino
                        ? _pixelOffset(
                            center: center,
                            point: client,
                            zoom: zoom,
                          )
                        : Offset.zero,
                    boxWidth: width,
                    boxHeight: height,
                    iconSize: _vehicleIconSize,
                    anchorBottom: false,
                    child: Image.asset(
                      isMoto
                          ? 'assets/img/icono_moto.png'
                          : 'assets/img/icono_carro.png',
                      width: _vehicleIconSize,
                      height: _vehicleIconSize,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Posiciona un ícono exacto sobre un punto del mapa, dado su [offset] en
/// píxeles respecto al centro de la imagen.
///
/// [anchorBottom] controla qué parte del ícono cae sobre el punto:
/// - `true` (pin/gota, ej. `map_pin_red.png`): la PUNTA, borde inferior
///   central del asset — `Center` sola centraría el cuadrado del ícono, no
///   la punta (mismo criterio que el pin de `_HomeClienteMap`).
/// - `false` (vista cenital, ej. `icono_carro.png`/`icono_moto.png`): el
///   CENTRO del asset, porque ahí es donde está el vehículo en un ícono
///   visto desde arriba — anclarlo por la punta lo desplazaría ~medio alto
///   de ícono hacia arriba de su ubicación real.
class _MapPinOverlay extends StatelessWidget {
  const _MapPinOverlay({
    required this.offset,
    required this.boxWidth,
    required this.boxHeight,
    required this.iconSize,
    required this.child,
    this.anchorBottom = true,
  });

  final Offset offset;
  final double boxWidth;
  final double boxHeight;
  final double iconSize;
  final Widget child;
  final bool anchorBottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: boxWidth / 2 + offset.dx - iconSize / 2,
      top: boxHeight / 2 + offset.dy - (anchorBottom ? iconSize : iconSize / 2),
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
}

/// Fondo mostrado si falla la imagen (sin red / sin key configurada) o si la
/// key de Remote Config está vacía. Evita el ícono de imagen rota y deja la
/// pantalla usable sin mapa.
class _MapaBusquedaPlaceholder extends StatelessWidget {
  const _MapaBusquedaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColores.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(
        Icons.map_outlined,
        size: 40,
        color: AppColores.textSecondary.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Loader acotado al cuadro del mapa mientras no hay ubicación del cliente
/// todavía, o mientras se descarga la imagen estática ya con ubicación.
class _MapaBusquedaCargando extends StatelessWidget {
  const _MapaBusquedaCargando();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColores.grey300.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}
