import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel, ContraofertaItem;
import 'package:taxi_app/utils/marker_icon_helper.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BuscandoTaxiView
// ─────────────────────────────────────────────────────────────────────────────

class BuscandoTaxiView extends StatefulWidget {
  final String? solicitudId;
  final double defaultMarkerHue;

  const BuscandoTaxiView({
    Key? key,
    this.solicitudId,
    this.defaultMarkerHue = BitmapDescriptor.hueYellow,
  }) : super(key: key);

  @override
  State<BuscandoTaxiView> createState() => _BuscandoTaxiViewState();
}

class _BuscandoTaxiViewState extends State<BuscandoTaxiView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BuscandoTaxiViewModel _vm;
  late final AnimationController _dotsController;

  GoogleMapController? _mapController;

  StreamSubscription<Map<String, LatLng>>? _conductoresSub;
  StreamSubscription<Map<String, LatLng>>? _conductoresConectadosSub;

  // Nuevas instancias en cada update para que didUpdateWidget detecte cambios
  Map<String, LatLng> _conductoresPositions = {};
  Map<String, LatLng> _conectadosPositions = {};
  LatLng? _clientLocation;

  Timer? _searchTimer;
  int _searchSeconds = 0;
  bool _notif5minEnviada = false;

  // Cancela la solicitud si la app pasa demasiado tiempo en segundo plano.
  Timer? _bgCancelTimer;
  // Cancela la solicitud 5 s después de que el motor Flutter se destruya.
  Timer? _detachedCancelTimer;
  // true cuando ya se navegó/canceló: evita acciones de ciclo de vida tardías.
  bool _flujoTerminado = false;
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

  // 6 min en segundo plano sin volver → cancelar solicitud.
  static const Duration _umbralBackgroundCancel = Duration(minutes: 6);
  // 5 s tras destrucción del motor → cancelar solicitud.
  static const Duration _umbralDetachedCancel = Duration(seconds: 5);
  static const int _segundosAviso5min = 300;

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

    _startSearchTimer();
    _initClientLocation();
    _subscribeConductores();
    _subscribeConductoresConectados();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_flujoTerminado) return;

    if (state == AppLifecycleState.detached) {
      // Motor Flutter destruido (app cerrada por completo).
      // Esperar 5 s para dar tiempo al SDK a enviar la escritura a Firestore.
      _detachedCancelTimer?.cancel();
      _detachedCancelTimer = Timer(_umbralDetachedCancel, () {
        if (!_flujoTerminado) _vm.marcarCanceladaPorInactividad();
      });
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // App en segundo plano: cancelar tras 6 min sin volver.
      _bgCancelTimer?.cancel();
      _bgCancelTimer = Timer(_umbralBackgroundCancel, () {
        if (!_flujoTerminado) _vm.marcarCanceladaPorInactividad();
      });
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _bgCancelTimer?.cancel();
      _detachedCancelTimer?.cancel();
    }
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeMostrarModalContraofertas();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  void _subscribeConductores() {
    _conductoresSub?.cancel();
    _conductoresSub = _vm.streamConductoresDisponibles().listen(
      (positions) {
        if (!mounted) return;
        setState(() {
          _conductoresPositions = Map<String, LatLng>.from(positions);
        });
      },
      onError: (_) {},
    );
  }

  void _subscribeConductoresConectados() {
    _conductoresConectadosSub?.cancel();
    _conductoresConectadosSub = _vm.streamConductoresConectados().listen(
      (positions) {
        if (!mounted) return;
        setState(() {
          _conectadosPositions = Map<String, LatLng>.from(positions);
        });
      },
      onError: (_) {},
    );
  }

  // ── Ubicación ─────────────────────────────────────────────────────────────

  Future<void> _initClientLocation() async {
    // 1. Mostrar posición cacheada inmediatamente (sin esperar GPS)
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('cli_last_lat');
      final lng = prefs.getDouble('cli_last_lng');
      if (lat != null && lng != null && mounted) {
        setState(() => _clientLocation = LatLng(lat, lng));
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(_clientLocation!, 14),
        );
      }
    } catch (_) {}

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
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(fresh, 14),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cli_last_lat', fresh.latitude);
      await prefs.setDouble('cli_last_lng', fresh.longitude);
    } catch (_) {}
  }

  // ── Timer de búsqueda ─────────────────────────────────────────────────────

  void _startSearchTimer() {
    _searchTimer?.cancel();
    _searchSeconds = 0;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _searchSeconds++);
      if (!_notif5minEnviada && _searchSeconds >= _segundosAviso5min) {
        _notif5minEnviada = true;
        _avisar5Minutos();
      }
    });
  }

  Future<void> _avisar5Minutos() async {
    try {
      await NotificacionesServicio.instance.showNotification(
        id: 1003,
        title: 'Llevas 5 minutos buscando',
        body: 'Aún no hay conductor. ¿Quieres aumentar tu oferta para '
            'conseguir uno más rápido?',
      );
    } catch (_) {}
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
    _flujoTerminado = true;
    _bgCancelTimer?.cancel();
    _detachedCancelTimer?.cancel();
    await _vm.detenerEscucha();
    if (!mounted) return;
    _searchTimer?.cancel();
    _conductoresConectadosSub?.cancel();
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
    _flujoTerminado = true;
    _bgCancelTimer?.cancel();
    _detachedCancelTimer?.cancel();
    await _vm.cancelarSolicitud();
    if (!mounted) return;
    _searchTimer?.cancel();
    _conductoresConectadosSub?.cancel();
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
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actualizar valor del servicio',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: buildSuggestions().map((value) {
                      return ActionChip(
                        label: Text(
                          '\$${_formatCurrency(value)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
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
                  const SizedBox(height: 12),
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
                              final ok =
                                  await _vm.actualizarValorServicio(next);
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
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
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
    _bgCancelTimer?.cancel();
    _detachedCancelTimer?.cancel();
    _conductoresSub?.cancel();
    _conductoresConectadosSub?.cancel();
    _searchTimer?.cancel();
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
        if (_flujoTerminado || _vm.isCancelling) return;
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
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    _buildOfertaActual(isTablet),
                    const SizedBox(height: 16),
                    _SonarMapWidget(
                      clientLocation: _clientLocation,
                      conductoresPositions: _conductoresPositions,
                      conectadosPositions: _conectadosPositions,
                      isMoto: _vm.isMotoSolicitud,
                      ampliarRango: _searchSeconds >= _segundosAviso5min,
                      mapHeight: mapHeight,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        if (_clientLocation != null) {
                          controller.animateCamera(
                            CameraUpdate.newLatLngZoom(_clientLocation!, 14),
                          );
                        }
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
        const SizedBox(width: 8),
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
          horizontal: 18,
          vertical: isTablet ? 18 : 16,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF22B567), verde],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
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
              width: 44,
              height: 44,
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
            const SizedBox(width: 14),
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
                  const SizedBox(height: 2),
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
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Editar',
                      style: TextStyle(
                        fontSize: 12.5,
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
            fontSize: isTablet ? 15 : 13,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        _buildSearchingDots(isTablet),
        const SizedBox(height: 10),
        Text(
          _formatDuration(_searchSeconds),
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
    if (_modalContraofertasAbierto || _flujoTerminado || _navegandoAViaje) return;
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
        if (mounted && !_flujoTerminado && !_navegandoAViaje) {
          _maybeMostrarModalContraofertas();
        }
      });
    });
  }

  Widget _buildModalContraofertas(BuildContext ctx) {
    final isTablet = MediaQuery.of(ctx).size.width >= 600;
    return AnimatedBuilder(
      animation: _vm,
      builder: (ctx, _) {
        final ofertas = _vm.contraofertas;
        // Cuando ya no quedan ofertas (aceptada/rechazadas), cerrar el modal.
        // Se usa el context del State (no ctx del dialog) para evitar que un
        // ctx en animación de salida haga double-pop y saque BuscandoTaxiView.
        // _modalContraofertasAbierto actúa como guard de un solo disparo.
        if (ofertas.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_modalContraofertasAbierto || _dismissingModal) return;
            _dismissingModal = true;
            Navigator.of(context).maybePop();
          });
        }
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          backgroundColor: AppColores.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.local_taxi,
                          color: AppColores.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Conductores que ofertaron (${ofertas.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: isTablet ? 18 : 16,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    'Elige la oferta que prefieras según valor y calificación.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: ofertas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _buildContraofertaCard(ofertas[i], isTablet),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Estrellas de calificación del conductor (promedio 0-5).
  Widget _buildEstrellas(double calif, int total) {
    if (total <= 0 && calif <= 0) {
      return const Text(
        'Conductor nuevo',
        style: TextStyle(fontSize: 11.5, color: AppColores.textSecondary),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          IconData icon;
          if (calif >= i + 1) {
            icon = Icons.star_rounded;
          } else if (calif >= i + 0.5) {
            icon = Icons.star_half_rounded;
          } else {
            icon = Icons.star_outline_rounded;
          }
          return Icon(icon, size: 15, color: AppColores.warning);
        }),
        const SizedBox(width: 4),
        Text(
          '${calif.toStringAsFixed(1)} ($total)',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColores.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildContraofertaCard(ContraofertaItem o, bool isTablet) {
    final isResponding =
        _respondingOffer[o.conductorId] == true || _vm.isRespondingCounteroffer;
    final hasPhoto = o.conductorFoto != null && o.conductorFoto!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.buttonPrimary, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: isTablet ? 26 : 22,
                  backgroundColor: AppColores.grey200,
                  backgroundImage:
                      hasPhoto ? NetworkImage(o.conductorFoto!) : null,
                  child: !hasPhoto
                      ? Icon(
                          Icons.person,
                          size: isTablet ? 28 : 24,
                          color: AppColores.textSecondary,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.conductorNombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 15 : 13,
                          color: AppColores.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (o.placa != null && o.placa!.isNotEmpty)
                        Text(
                          o.placa!,
                          style: TextStyle(
                            fontSize: isTablet ? 13 : 11,
                            color: AppColores.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 4),
                      _buildEstrellas(o.calificacion, o.totalCalificaciones),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '\$${_formatCurrency(o.valor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isTablet ? 19 : 17,
                    color: AppColores.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Botones debajo de la calificación, ocupando el ancho.
            Row(
              children: [
                Expanded(
                  child: _OfertaButton(
                    label: 'Rechazar',
                    color: AppColores.grey200,
                    textColor: AppColores.textSecondary,
                    isLoading: isResponding,
                    onTap: () => _rechazarOferta(o.conductorId),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OfertaButton(
                    label: 'Aceptar',
                    color: AppColores.buttonPrimary,
                    textColor: AppColores.textWhite,
                    isLoading: isResponding,
                    onTap: () => _aceptarOferta(o.conductorId),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      height: 48,
      child: ElevatedButton(
        onPressed: _vm.isCancelling ? null : _cancelSolicitud,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColores.error,
          foregroundColor: AppColores.textWhite,
          disabledBackgroundColor: AppColores.grey400,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontSize: isTablet ? 16 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _vm.isCancelling
            ? const SizedBox(
                width: 18,
                height: 18,
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
              margin: const EdgeInsets.symmetric(horizontal: 5),
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
// _SonarMapWidget
// Gestiona la animación del sonar y los marcadores del mapa de forma aislada,
// evitando que el timer de 350ms reconstruya el árbol principal.
// ─────────────────────────────────────────────────────────────────────────────

class _SonarMapWidget extends StatefulWidget {
  const _SonarMapWidget({
    required this.clientLocation,
    required this.conductoresPositions,
    required this.conectadosPositions,
    required this.isMoto,
    required this.ampliarRango,
    required this.mapHeight,
    required this.onMapCreated,
  });

  final LatLng? clientLocation;
  final Map<String, LatLng> conductoresPositions;
  final Map<String, LatLng> conectadosPositions;
  final bool isMoto;
  final bool ampliarRango;
  final double mapHeight;
  final void Function(GoogleMapController) onMapCreated;

  @override
  State<_SonarMapWidget> createState() => _SonarMapWidgetState();
}

class _SonarMapWidgetState extends State<_SonarMapWidget> {
  static const _defaultCenter = LatLng(8.2595534, -73.353469);

  BitmapDescriptor? _taxiIcon;
  BitmapDescriptor? _smallTaxiIcon;
  BitmapDescriptor? _bigTaxiIcon;
  BitmapDescriptor? _motoIcon;

  double _sonarRadius = 220.0;
  // Radio máximo del sonar; se amplía tras 5 min sin encontrar conductor.
  double get _maxSonarRadius => widget.ampliarRango ? 1500.0 : 700.0;
  Timer? _sonarTimer;
  Set<Circle> _sonarCircles = {};
  Set<Circle> _clientCircles = {};
  Set<Marker> _taxiMarkers = {};
  Set<Marker> _conectadosMarkers = {};
  final Set<String> _visibleConectadosIds = {};

  @override
  void initState() {
    super.initState();
    _loadTaxiIcon();
    _loadSmallTaxiIcon();
    _loadMotoIcon();
    _updateClientCircle();
    _startSonarTimer();
  }

  Future<void> _loadMotoIcon() async {
    try {
      _motoIcon = await MarkerIconHelper.fromIcon(
        Icons.two_wheeler_rounded,
        60,
        const Color(0xFF111111),
      );
      if (!mounted) return;
      _updateTaxiMarkers();
      _updateVisibleConectadosMarkers();
      setState(() {});
    } catch (_) {}
  }

  @override
  void didUpdateWidget(_SonarMapWidget old) {
    super.didUpdateWidget(old);
    if (old.conductoresPositions != widget.conductoresPositions ||
        old.isMoto != widget.isMoto) {
      _updateTaxiMarkers();
    }
    if (old.conectadosPositions != widget.conectadosPositions ||
        old.isMoto != widget.isMoto) {
      _updateVisibleConectadosMarkers();
    }
    if (old.clientLocation != widget.clientLocation) {
      _updateClientCircle();
    }
  }

  @override
  void dispose() {
    _sonarTimer?.cancel();
    super.dispose();
  }

  // ── Sonar ─────────────────────────────────────────────────────────────────

  void _startSonarTimer() {
    _sonarTimer?.cancel();
    _sonarTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!mounted) return;
      setState(() {
        _sonarRadius += 50;
        if (_sonarRadius > _maxSonarRadius) _sonarRadius = 250;
        _sonarCircles = {
          Circle(
            circleId: const CircleId('sonar'),
            center: widget.clientLocation ?? _defaultCenter,
            radius: _sonarRadius,
            strokeColor: AppColores.primary,
            strokeWidth: 2,
            fillColor: AppColores.primary.withValues(alpha: 0.08),
          ),
        };
        _updateVisibleConectadosMarkers();
      });
    });
  }

  void _updateClientCircle() {
    final loc = widget.clientLocation;
    if (loc == null) {
      _clientCircles = {};
      return;
    }
    _clientCircles = {
      Circle(
        circleId: const CircleId('client_point'),
        center: loc,
        radius: 30,
        strokeColor: AppColores.primary,
        strokeWidth: 2,
        fillColor: AppColores.primary,
      ),
    };
  }

  // ── Marcadores de taxis disponibles ───────────────────────────────────────

  void _updateTaxiMarkers() {
    if (!mounted) return;
    final isMoto = widget.isMoto;
    if (!isMoto && _taxiIcon == null) {
      setState(() => _taxiMarkers = {});
      return;
    }
    final motoIcon = _motoIcon ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    final markers = widget.conductoresPositions.entries.map((e) {
      return Marker(
        markerId: MarkerId('taxi_${e.key}'),
        position: e.value,
        icon: isMoto ? motoIcon : _taxiIcon!,
        infoWindow: InfoWindow(
          title: isMoto ? 'Moto cercana' : 'Taxi cercano',
        ),
      );
    }).toSet();
    setState(() => _taxiMarkers = markers);
  }

  // ── Marcadores de conductores conectados (filtrados por sonar) ────────────

  void _updateVisibleConectadosMarkers() {
    final center = widget.clientLocation ?? _defaultCenter;
    final isMoto = widget.isMoto;
    final visible = <Marker>{};
    final newVisibleIds = <String>{};

    for (final entry in widget.conectadosPositions.entries) {
      final id = entry.key;
      final pos = entry.value;
      final distance = Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (distance > _sonarRadius) continue;

      newVisibleIds.add(id);
      final isNew = !_visibleConectadosIds.contains(id);

      final icon = isMoto
          ? (_motoIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange))
          : (isNew
              ? (_bigTaxiIcon ??
                  _smallTaxiIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueYellow,
                  ))
              : (_smallTaxiIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueYellow,
                  )));

      visible.add(
        Marker(
          markerId: MarkerId('conectado_$id'),
          position: pos,
          icon: icon,
          infoWindow: InfoWindow(
            title: isMoto
                ? 'Conductor de moto conectado'
                : 'Conductor conectado',
          ),
        ),
      );

      // Después de un breve instante, reducir el ícono al tamaño pequeño
      if (isNew) {
        Timer(const Duration(milliseconds: 420), () {
          if (!mounted) return;
          final smallIcon = isMoto
              ? (_motoIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange,
                  ))
              : (_smallTaxiIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueYellow,
                  ));
          setState(() {
            _conectadosMarkers = {
              ..._conectadosMarkers.where(
                (m) => m.markerId.value != 'conectado_$id',
              ),
              Marker(
                markerId: MarkerId('conectado_$id'),
                position: pos,
                icon: smallIcon,
                infoWindow: InfoWindow(
                  title: isMoto
                      ? 'Conductor de moto conectado'
                      : 'Conductor conectado',
                ),
              ),
            };
          });
        });
      }
    }

    _visibleConectadosIds
      ..clear()
      ..addAll(newVisibleIds);

    // Preservar marcadores transitorios (en medio de la animación de tamaño)
    final transient = _conectadosMarkers
        .where(
          (m) => newVisibleIds.contains(
            m.markerId.value.replaceFirst('conectado_', ''),
          ),
        )
        .toSet();
    _conectadosMarkers = {...visible, ...transient};
  }

  // ── Carga de íconos ───────────────────────────────────────────────────────

  Future<void> _loadTaxiIcon() async {
    try {
      _taxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        60,
        const Color(0xFF111111),
      );
      if (!mounted) return;
      _updateTaxiMarkers();
    } catch (_) {}
  }

  Future<void> _loadSmallTaxiIcon() async {
    try {
      _smallTaxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        54,
        const Color(0xFF111111),
      );
      if (!mounted) return;
      _bigTaxiIcon = await MarkerIconHelper.fromIcon(
        Icons.directions_car_rounded,
        70,
        const Color(0xFF111111),
      );
      if (!mounted) return;
      setState(() {});
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final center = widget.clientLocation ?? _defaultCenter;
    return Container(
      width: double.infinity,
      height: widget.mapHeight,
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Mapagoogle(
          initialTarget: center,
          initialZoom: 14,
          markers: {..._taxiMarkers, ..._conectadosMarkers},
          circles: {..._sonarCircles, ..._clientCircles},
          onMapCreated: widget.onMapCreated,
          zoomGesturesEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _OfertaButton — botón de aceptar/rechazar con estado de carga
// ─────────────────────────────────────────────────────────────────────────────

class _OfertaButton extends StatelessWidget {
  const _OfertaButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sin spinner: solo se atenúa y se deshabilita mientras procesa, para
    // evitar doble toque. La confirmación visual la da la pantalla
    // "Conductor encontrado" al aceptar.
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: isLoading ? 0.6 : 1.0,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
