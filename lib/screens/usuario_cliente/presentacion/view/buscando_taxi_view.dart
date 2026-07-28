import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart' hide DeviceType;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel;
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/contraofertas_modal.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/widgets/sonar_map_widget.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BuscandoTaxiView
// ─────────────────────────────────────────────────────────────────────────────

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;
  final double defaultMarkerHue;
  // Ubicación de recogida elegida en DetailsSolicitud (widget.origen). Al
  // llegar aquí ya no hace falta esperar GPS/caché para centrar el mapa: se
  // usa directamente el punto que el cliente ya confirmó como su recogida.
  final LatLng? initialClientLocation;

  const BuscandoTaxiView({
    Key? key,
    this.solicitudId,
    this.defaultMarkerHue = BitmapDescriptor.hueYellow,
    this.initialClientLocation,
  }) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BuscandoTaxiViewModel _vm;
  late final AnimationController _dotsController;

  GoogleMapController? _mapController;

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
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Centra de una vez con el punto de recogida ya elegido en
    // DetailsSolicitud — no hay que esperar a caché/GPS para dibujar el mapa.
    _clientLocation = widget.initialClientLocation;

    _vm.startSearchTimer();
    if (widget.initialClientLocation == null) {
      // Solo si no llegó ubicación desde DetailsSolicitud recurrimos a
      // caché/GPS como respaldo (compatibilidad con navegación antigua).
      _initClientLocation();
    }
    _vm.subscribeConductores();
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
  }

  // ── Ubicación ─────────────────────────────────────────────────────────────

  Future<void> _initClientLocation() async {
    // 1. Mostrar posición cacheada inmediatamente (sin esperar GPS)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('cli_last_lat');
      final lng = prefs.getDouble('cli_last_lng');
      if (lat != null && lng != null && mounted) {
        // Recentrar queda a cargo de SonarMapWidget.didUpdateWidget al
        // recibir el nuevo clientLocation (ver _maybeRecenter) — así hay un
        // solo lugar decidiendo cuándo mover la cámara, con el umbral de
        // distancia mínima que evita el "salto" por ruido de GPS.
        setState(() => _clientLocation = LatLng(lat, lng));
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
      nextBuilder: (_) => TripTrackingScreen(
        solicitudId: solicitudId,
        currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
        cancelledBy: 'cliente',
      ),
      title: 'Conductor encontrado',
      subtitle: 'Preparando tu ruta y detalles del viaje...',
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

  Future<void> _abrirModalEditarValor() async {
    String formatInput(String raw) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return '';
      final parsed = int.tryParse(digits) ?? 0;
      return _formatCurrency(parsed);
    }

    final initialDigits = _vm.valorServicioActual > 0
        ? _vm.valorServicioActual.round().toString()
        : '10000';
    final initialFormatted = formatInput(initialDigits);
    final controller = TextEditingController(text: initialFormatted)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialFormatted.length,
      );
    bool isFormatting = false;

    List<int> buildSuggestions() {
      final current = int.tryParse(initialDigits) ?? 5000;
      final base = current < 5000 ? 5000 : current;
      return [base + 500, base + 1000, base + 1500, base + 2000];
    }

    _modalEditarAbierto = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final keyboardInset = media.viewInsets.bottom;
        final bottomGap = keyboardInset > 0
            ? keyboardInset + 12
            : media.viewPadding.bottom + 12;

        return Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 12, bottomGap),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actualizar valor del servicio',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18.sp,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      if (isFormatting) return;
                      final formatted = formatInput(value);
                      if (formatted == value) return;
                      isFormatting = true;
                      controller.value = TextEditingValue(
                        text: formatted,
                        selection: TextSelection.collapsed(
                          offset: formatted.length,
                        ),
                      );
                      isFormatting = false;
                    },
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      hintText: 'Ej: 11.000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: buildSuggestions().map((value) {
                      return ActionChip(
                        label: Text(
                          '\$${_formatCurrency(value)}',
                          style: TextStyle(fontSize: 13.sp),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 3.h,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () {
                          final formatted = _formatCurrency(value);
                          controller.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 12.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _vm.isUpdatingValor
                          ? null
                          : () async {
                              final digits = controller.text.replaceAll(
                                RegExp(r'[^0-9]'),
                                '',
                              );
                              if (digits.isEmpty) return;
                              final next = double.tryParse(digits);
                              if (next == null || next <= 0) return;
                              final messenger = ScaffoldMessenger.of(context);
                              final navigator = Navigator.of(ctx);
                              final ok = await _vm.actualizarValorServicio(
                                next,
                              );
                              if (!mounted) return;
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Valor actualizado, seguimos buscando conductor.'
                                        : 'No se pudo actualizar el valor.',
                                  ),
                                ),
                              );
                            },
                      child: _vm.isUpdatingValor
                          ? SizedBox(
                              width: 18.w,
                              height: 18.h,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar nuevo valor'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    _modalEditarAbierto = false;
    controller.dispose();
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapController?.dispose();
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
    final mapHeight = ResponsiveHelper.hp(
      context,
      isTablet ? 42 : 46,
    ).clamp(200.0, 620.0);

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
        backgroundColor: AppColores.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado fijo arriba
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 32 : 16,
                  12,
                  isTablet ? 32 : 16,
                  0,
                ),
                child: _buildHeader(isTablet),
              ),
              // Oferta + mapa centrados; el texto "buscando" queda equidistante
              // entre el mapa y el botón cancelar (mismos Spacer arriba/abajo).
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 32 : 16,
                    vertical: 8.h,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      _buildOfertaActual(isTablet),
                      SizedBox(height: 16.h),
                      SonarMapWidget(
                        clientLocation: _clientLocation,
                        conductoresPositions: _vm.conductoresPositions,
                        conectadosPositions: _vm.conectadosPositions,
                        isMoto: _vm.isMotoSolicitud,
                        ampliarRango: _vm.searchSeconds >= BuscandoTaxiViewModel.segundosAviso5min,
                        mapHeight: mapHeight,
                        onMapCreated: (controller) {
                          // El zoom/centro inicial ya lo fija Mapagoogle con
                          // initialTarget/initialZoom; re-animar aquí a otro
                          // zoom (14) lo deshacía apenas se creaba el mapa.
                          // Los siguientes cambios de ubicación los recentra
                          // el propio SonarMapWidget (ver _maybeRecenter).
                          _mapController = controller;
                        },
                      ),
                      const Spacer(),
                      _buildSearchingSection(isTablet),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
              // Botón cancelar siempre visible en el borde inferior
              _buildBottomCancelBar(isTablet, media),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secciones del build ───────────────────────────────────────────────────

  Widget _buildHeader(bool isTablet) {
    return Row(
      children: [
        const Icon(Icons.search, color: AppColores.primary, size: 22),
        SizedBox(width: 8.w),
        Text(
          'Buscando...',
          style: TextStyle(
            fontSize: isTablet ? 22 : 18,
            fontWeight: FontWeight.w800,
            color: AppColores.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildOfertaActual(bool isTablet) {
    const Color verde = Color(0xFF1F9D55);
    return GestureDetector(
      onTap: _vm.isUpdatingValor ? null : _abrirModalEditarValor,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 18.w,
          vertical: isTablet ? 18 : 16,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF22B567), verde],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: verde.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44.w,
              height: 44.h,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tu oferta',
                    style: TextStyle(
                      fontSize: isTablet ? 14 : 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '\$${_formatCurrency(_vm.valorServicioActual)}',
                    style: TextStyle(
                      fontSize: isTablet ? 32 : 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            if (_vm.isUpdatingValor)
              SizedBox(
                width: 20.w,
                height: 20.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 14, color: Colors.white),
                    SizedBox(width: 4.w),
                    Text(
                      'Editar',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingSection(bool isTablet) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Buscando el conductor más cercano para ti.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColores.textSecondary,
            fontSize: isTablet ? 17 : 15,
            fontWeight: FontWeight.w600,
            height: 1.4.h,
          ),
        ),
        SizedBox(height: 14.h),
        _buildSearchingDots(isTablet),
        SizedBox(height: 10.h),
        Text(
          _formatDuration(_vm.searchSeconds),
          style: TextStyle(
            fontSize: isTablet ? 28 : 24,
            fontWeight: FontWeight.w700,
            color: AppColores.primary,
            letterSpacing: 2,
          ),
        ),
      ],
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

  Widget _buildBottomCancelBar(bool isTablet, MediaQueryData media) {
    // Inset real de la barra de navegación + separación, para que el botón
    // no quede pegado a la barra de Android (gestos o 3 botones).
    final bottomPad = media.padding.bottom + 14.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 16,
        isTablet ? 20 : 14,
        isTablet ? 32 : 16,
        bottomPad,
      ),
      decoration: const BoxDecoration(
        color: AppColores.background,
        border: Border(top: BorderSide(color: AppColores.borderSubtle)),
      ),
      child: _buildCancelButton(isTablet),
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
