import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel, ContraofertaItem;
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
    with SingleTickerProviderStateMixin {
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

  // Estado UI-only: qué conductores están siendo respondidos
  final Map<String, bool> _respondingOffer = {};

  @override
  void initState() {
    super.initState();
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

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {});
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
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _clientLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_clientLocation!, 14),
      );
    } catch (_) {}
  }

  // ── Timer de búsqueda ─────────────────────────────────────────────────────

  void _startSearchTimer() {
    _searchTimer?.cancel();
    _searchSeconds = 0;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _searchSeconds++);
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _onSolicitudAsignada(String solicitudId) async {
    if (!mounted) return;
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
        onSolicitudCancelada: () {
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeClienteView()),
            (route) => false,
          );
        },
      ),
      title: 'Conductor encontrado',
      subtitle: 'Preparando tu ruta y detalles del viaje...',
    );
  }

  Future<void> _cancelSolicitud() async {
    if (_vm.isCancelling) return;
    await _vm.cancelarSolicitud();
    if (!mounted) return;
    _searchTimer?.cancel();
    _conductoresConectadosSub?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
    );
  }

  Future<void> _aceptarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true) return;
    setState(() => _respondingOffer[conductorId] = true);
    final ok = await _vm.aceptarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _respondingOffer.remove(conductorId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo aceptar la oferta.')),
      );
      return;
    }
    // Aceptación exitosa: Firestore ya tiene estado='asignado'.
    // Navegar directamente sin esperar el round-trip del listener.
    final id = widget.solicitudId;
    if (id != null) {
      await _onSolicitudAsignada(id);
    }
    // Fallback: si solicitudId es null, el listener de iniciarEscucha
    // detectará estado='asignado' y llamará onAsignada.
  }

  Future<void> _rechazarOferta(String conductorId) async {
    if (_respondingOffer[conductorId] == true) return;
    setState(() => _respondingOffer[conductorId] = true);
    final ok = await _vm.rechazarContraofertaDeConductor(conductorId);
    if (!mounted) return;
    setState(() => _respondingOffer.remove(conductorId));
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
    controller.dispose();
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
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
      isTablet ? 35 : 38,
    ).clamp(160.0, 560.0);

    return Scaffold(
      backgroundColor: AppColores.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ①②③ Área scrollable: encabezado + mapa + oferta + (dots si no hay ofertas)
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: isTablet ? 32 : 16,
                      right: isTablet ? 32 : 16,
                      top: 12,
                      bottom: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(isTablet),
                        const SizedBox(height: 14),
                        _SonarMapWidget(
                          clientLocation: _clientLocation,
                          conductoresPositions: _conductoresPositions,
                          conectadosPositions: _conectadosPositions,
                          isMoto: _vm.isMotoSolicitud,
                          mapHeight: mapHeight,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            if (_clientLocation != null) {
                              controller.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  _clientLocation!,
                                  14,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildOfertaActual(isTablet),
                        if (_vm.contraofertas.isEmpty) ...[
                          const SizedBox(height: 14),
                          _buildSearchingSection(isTablet),
                        ],
                      ],
                    ),
                  ),
                ),
                // ④ Panel de contraofertas fijo entre el scroll y el botón
                if (_vm.contraofertas.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        isTablet ? 32 : 16,
                        8,
                        isTablet ? 32 : 16,
                        4,
                      ),
                      child: _buildContraofertasPanel(isTablet),
                    ),
                  ),
                // ⑤ Botón cancelar siempre visible en el borde inferior
                _buildBottomCancelBar(isTablet, media),
              ],
            ),
            // FAB para centrar el mapa en la ubicación del cliente
            Positioned(
              right: isTablet ? 48 : 24,
              top: 72,
              child: FloatingActionButton.small(
                heroTag: 'center_client',
                backgroundColor: Colors.white,
                foregroundColor: AppColores.textSecondary,
                elevation: 3,
                onPressed: () {
                  if (_clientLocation == null) return;
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(_clientLocation!, 14),
                  );
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
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
        Expanded(
          child: Text(
            'Buscando taxi...',
            style: TextStyle(
              fontSize: isTablet ? 22 : 18,
              fontWeight: FontWeight.w800,
              color: AppColores.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColores.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColores.borderSubtle),
          ),
          child: Text(
            _formatDuration(_searchSeconds),
            style: TextStyle(
              fontSize: isTablet ? 15 : 13,
              fontWeight: FontWeight.w700,
              color: AppColores.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfertaActual(bool isTablet) {
    return GestureDetector(
      onTap: _vm.isUpdatingValor ? null : _abrirModalEditarValor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColores.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColores.borderSubtle),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.monetization_on_outlined,
              color: AppColores.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tu oferta: \$${_formatCurrency(_vm.valorServicioActual)}',
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.w700,
                  color: AppColores.textPrimary,
                ),
              ),
            ),
            if (_vm.isUpdatingValor)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.edit_outlined,
                size: 16,
                color: AppColores.textSecondary,
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
      ],
    );
  }

  Widget _buildContraofertasPanel(bool isTablet) {
    final ofertas = _vm.contraofertas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.local_taxi, color: AppColores.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              'Ofertas de conductores (${ofertas.length})',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: isTablet ? 16 : 14,
                color: AppColores.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ofertas.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _buildContraofertaCard(ofertas[i], isTablet),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: isTablet ? 26 : 22,
              backgroundColor: AppColores.grey200,
              backgroundImage: hasPhoto ? NetworkImage(o.conductorFoto!) : null,
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
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\$${_formatCurrency(o.valor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isTablet ? 18 : 16,
                    color: AppColores.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _OfertaButton(
                      label: 'Rechazar',
                      color: AppColores.grey200,
                      textColor: AppColores.textSecondary,
                      isLoading: isResponding,
                      onTap: () => _rechazarOferta(o.conductorId),
                    ),
                    const SizedBox(width: 6),
                    _OfertaButton(
                      label: 'Aceptar',
                      color: AppColores.buttonPrimary,
                      textColor: AppColores.textPrimary,
                      isLoading: isResponding,
                      onTap: () => _aceptarOferta(o.conductorId),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCancelBar(bool isTablet, MediaQueryData media) {
    final bottomPad = media.padding.bottom > 0 ? media.padding.bottom : 16.0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 16,
        8,
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
    required this.mapHeight,
    required this.onMapCreated,
  });

  final LatLng? clientLocation;
  final Map<String, LatLng> conductoresPositions;
  final Map<String, LatLng> conectadosPositions;
  final bool isMoto;
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

  double _sonarRadius = 220.0;
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
    _updateClientCircle();
    _startSonarTimer();
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
        if (_sonarRadius > 700) _sonarRadius = 250;
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
    final markers = widget.conductoresPositions.entries.map((e) {
      return Marker(
        markerId: MarkerId('taxi_${e.key}'),
        position: e.value,
        icon: isMoto
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
            : _taxiIcon!,
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
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
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
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                )
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
      _taxiIcon = await _bitmapDescriptorFromAsset(
        'assets/img/taxi_icon.png',
        26,
      );
      if (!mounted) return;
      _updateTaxiMarkers();
    } catch (_) {}
  }

  Future<void> _loadSmallTaxiIcon() async {
    try {
      _smallTaxiIcon = await _bitmapDescriptorFromAsset(
        'assets/img/taxi_icon.png',
        24,
      );
      _bigTaxiIcon = await _bitmapDescriptorFromAsset(
        'assets/img/taxi_icon.png',
        34,
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
// Helper: carga un asset como BitmapDescriptor escalado
// ─────────────────────────────────────────────────────────────────────────────

Future<BitmapDescriptor> _bitmapDescriptorFromAsset(
  String path,
  int targetWidth,
) async {
  final byteData = await rootBundle.load(path);
  final bytes = byteData.buffer.asUint8List();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
  );
  final frame = await codec.getNextFrame();
  final pngBytes = await frame.image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  return BitmapDescriptor.bytes(pngBytes!.buffer.asUint8List());
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
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isLoading ? AppColores.grey200 : color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColores.textSecondary,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
      ),
    );
  }
}
