import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';
import 'package:taxi_app/features/trip_tracking_cliente/widgets/trip_details_sheet.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteDestinoView.dart';
import 'package:taxi_app/routes/app_routes.dart';

import '../controllers/solicitud_estado_controller.dart';
import '../viewmodels/trip_tracking_viewmodel.dart';

import '../widgets/user_trip_info_card.dart';
import 'trip_chat_screen.dart';

class TripTrackingScreen extends StatefulWidget {
  const TripTrackingScreen({
    super.key,
    required this.solicitudId,
    required this.currentUserId,
    this.cancelledBy = 'cliente',
  });

  final String solicitudId;
  final String currentUserId;
  final String cancelledBy;

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  GoogleMapController? _mapController;
  late final SolicitudEstadoController _estadoController;
  BitmapDescriptor? _taxiMarkerIcon;
  Timer? _cancelDisableTimer;
  bool _cancelAllowed = true;
  bool _cancelAllowedBeforeModal = true;
  bool _initialCameraApplied = false;
  bool _cancelledNavigationDone = false;
  bool _rutaDestinoNavigationDone = false;

  String? _lastEstadoProcesado;
  String? _lastPersistedStatus;

  @override
  void initState() {
    super.initState();
    _estadoController = SolicitudEstadoController();
    // Listen to wait modal visibility to disable cancel button while modal is open.
    _estadoController.waitModalVisible.addListener(() {
      if (!mounted) return;
      final visible = _estadoController.waitModalVisible.value;
      setState(() {
        if (visible) {
          _cancelAllowedBeforeModal = _cancelAllowed;
          _cancelAllowed = false;
        } else {
          _cancelAllowed = _cancelAllowedBeforeModal;
        }
      });
    });
    _loadTaxiMarkerIcon();
    _startCancelDisableTimer();
    // Persist current screen so reload restores this exact view
    try {
      SessionHelper.setActiveSolicitudScreen('trip_tracking');
    } catch (_) {}
  }

  void _startCancelDisableTimer() {
    _cancelAllowed = true;
    _cancelDisableTimer?.cancel();
    _cancelDisableTimer = Timer(const Duration(minutes: 5), () {
      if (!mounted) return;
      setState(() {
        _cancelAllowed = false;
      });
    });
  }

  // Detecta si el dispositivo tiene barra de navegación inferior (Android/iOS)
  bool hasNavigationBar(BuildContext context) {
    return MediaQuery.of(context).padding.bottom > 0;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TripTrackingViewModel>(
      create: (_) => TripTrackingViewModel(
        solicitudId: widget.solicitudId,
        currentUserId: widget.currentUserId,
        cancelledBy: widget.cancelledBy,
      )..init(),
      child: Consumer<TripTrackingViewModel>(
        builder: (context, vm, _) {
          _syncSolicitudPersistence(vm);
          _handleTripStateIfNeeded(vm);
          _handleSolicitudCanceladaIfNeeded(vm);
          _fitInitialCameraIfNeeded(vm);

          final markers = <Marker>{
            if (vm.conductorLatLng != null)
              Marker(
                markerId: const MarkerId('conductor'),
                position: vm.conductorLatLng!,
                infoWindow: const InfoWindow(title: 'Conductor'),
                icon:
                    _taxiMarkerIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                rotation: vm.conductorHeading,
                flat: true,
                anchor: const Offset(0.5, 0.5),
              ),
          };

          final polylines = <Polyline>{
            if (vm.routePoints.length >= 2)
              Polyline(
                polylineId: const PolylineId('ruta_real_time'),
                points: vm.routePoints,
                color: AppColores.buttonPrimary,
                width: 5,
              ),
          };

          final initialTarget =
              vm.clienteLatLng ??
              vm.conductorLatLng ??
              const LatLng(8.2595534, -73.353469);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
            child: PopScope(
              canPop: false,
              child: Scaffold(
                body: Builder(
                  builder: (ctx) {
                    final mq = MediaQuery.of(ctx);
                    final screenH = mq.size.height;
                    final safeBottom = mq.padding.bottom;

                    return Stack(
                      children: [
                        // Map area (100%)
                        SizedBox(
                          height: screenH,
                          width: double.infinity,
                          child: Stack(
                            children: [
                              GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: initialTarget,
                                  zoom: 14,
                                ),
                                myLocationEnabled: true,
                                myLocationButtonEnabled: false,
                                compassEnabled: true,
                                padding: EdgeInsets.only(
                                  top:
                                      mq.padding.top +
                                      350, // Evita que se tape con la card superior
                                  bottom: safeBottom + 20,
                                ),
                                markers: markers,
                                polylines: polylines,
                                onMapCreated: (controller) {
                                  _mapController = controller;
                                  _fitInitialCameraIfNeeded(vm);
                                },
                              ),
                              if (vm.isOffline ||
                                  vm.errorText?.toLowerCase().contains(
                                        'cache',
                                      ) ==
                                      true)
                                Positioned(
                                  top:
                                      mq.padding.top +
                                      280, // Debajo de la card superior
                                  left: 20,
                                  right: 20,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColores.warning,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: AppColores.overlayLight,
                                          blurRadius: 8,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.wifi_off_rounded,
                                          color: AppColores.textWhite,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Sin conexión. Mostrando datos guardados.',
                                            style: TextStyle(
                                              color: AppColores.textWhite,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: 16,
                                bottom: safeBottom + 16,
                                child: FloatingActionButton(
                                  heroTag: 'focus_trip_tracking',
                                  backgroundColor: AppColores.buttonPrimary,
                                  onPressed: () => _toggleFocus(vm),
                                  child: Icon(
                                    vm.focusMode == MapFocusMode.clientOnly
                                        ? Icons.person_pin_circle
                                        : Icons.fit_screen,
                                    color: AppColores.textWhite,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Top Card (UserTripInfoCard con nuevo diseño)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: UserTripInfoCard(
                            name: vm.nombreUsuarioCard,
                            vehiclePlate: vm.placaVehiculo,
                            userPhotoUrl: vm.fotoUsuario,
                            vehiclePhotoUrl: vm.fotoVehiculo,
                            unreadCount: vm.unreadCount,
                            isCancelling: vm.isCancelling,
                            onPrimaryAction: () => _openChat(vm),
                            onCancel: () => _onCancelPressed(vm),
                            cancelEnabled: _cancelAllowed,
                            etaText: vm.etaTexto,
                            distanceText: vm.distanciaTexto,
                            onHelp: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.white,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                                builder: (ctx) {
                                  return SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24.0,
                                        vertical: 16.0,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 20,
                                                backgroundColor:
                                                    AppColores.primary,
                                                backgroundImage:
                                                    vm.fotoUsuario.isNotEmpty
                                                    ? NetworkImage(
                                                        vm.fotoUsuario,
                                                      )
                                                    : null,
                                                child: vm.fotoUsuario.isEmpty
                                                    ? const Icon(
                                                        Icons.person,
                                                        size: 24,
                                                        color: Colors.white,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  vm.nombreUsuarioCard,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color:
                                                        AppColores.textPrimary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 24),
                                          const Divider(
                                            height: 1,
                                            color: Colors.black12,
                                          ),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              '¿Cuál es el estado de mi solicitud?',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.black54,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              Navigator.of(context).pushNamed(
                                                AppRoutes.ayudaEstadoSolicitud,
                                                arguments: {
                                                  'solicitudId': vm.solicitudId,
                                                },
                                              );
                                            },
                                          ),
                                          const Divider(
                                            height: 1,
                                            color: Colors.black12,
                                          ),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Cambiar mi dirección',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.black54,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              Navigator.of(context).pushNamed(
                                                AppRoutes.ayudaCambiarDestino,
                                                arguments: {
                                                  'solicitudId': vm.solicitudId,
                                                  'direccion':
                                                      vm.destinoDireccion,
                                                },
                                              );
                                            },
                                          ),
                                          const Divider(
                                            height: 1,
                                            color: Colors.black12,
                                          ),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Revisar o modificar mi pago',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.black54,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              Navigator.of(context).pushNamed(
                                                AppRoutes.ayudaMetodoPago,
                                                arguments: {
                                                  'solicitudId': vm.solicitudId,
                                                  'metodoActual': vm.metodoPago,
                                                },
                                              );
                                            },
                                          ),
                                          const Divider(
                                            height: 1,
                                            color: Colors.black12,
                                          ),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Problemas con el conductor',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.black54,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              Navigator.of(context).pushNamed(
                                                AppRoutes
                                                    .ayudaProblemasConductor,
                                                arguments: {
                                                  'solicitudId': vm.solicitudId,
                                                  'nombreConductor':
                                                      vm.nombreConductor,
                                                },
                                              );
                                            },
                                          ),
                                          const Divider(
                                            height: 1,
                                            color: Colors.black12,
                                          ),
                                          ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              '¿Puedo cancelar mi solicitud?',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                              color: Colors.black54,
                                            ),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              // Confirmación con modal centrado.
                                              _onCancelPressed(vm);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            onDetails: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24),
                                  ),
                                ),
                                isScrollControlled: true,
                                builder: (_) => TripDetailsSheet(
                                  tituloPersona: 'Conductor',
                                  nombrePersona: vm.nombreConductor,
                                  fotoPersona: vm.fotoUsuario,
                                  calificacion: vm.calificacionConductor,
                                  totalCalificaciones:
                                      vm.totalCalificacionesConductor,
                                  fotoVehiculo: vm.fotoVehiculo,
                                  placa: vm.placaVehiculo,
                                  labelRecoger: 'Tu ubicación',
                                  direccionRecoger: vm.tuUbicacionTexto,
                                  direccionDestino: vm.destinoDireccion,
                                  valorServicio: vm.valorServicio,
                                  metodoPago: vm.metodoPago,
                                ),
                              );
                            },
                          ),
                        ),

                        if (vm.isLoading || vm.isUpdatingRoute)
                          Positioned.fill(
                            child: ColoredBox(
                              color: AppColores.overlayLight,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: AppColores.primary,
                                    ),
                                    if (vm.isUpdatingRoute) ...[
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Cargando ruta...',
                                        style: TextStyle(
                                          color: AppColores.primary,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (vm.isOffline)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.wifi_off_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 10),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Sin conexión',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Esperando señal...',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleTripStateIfNeeded(TripTrackingViewModel vm) async {
    final estado = vm.solicitud?.estado;
    if (estado == null || estado.isEmpty) return;

    final normalizado = SolicitudEstadoController.normalizeEstado(estado);
    // Avoid triggering navigation on initial load when status is 'asignado'.
    // This prevents reload from immediately replacing this screen.
    if (_lastEstadoProcesado == null && normalizado == 'asignado') {
      _lastEstadoProcesado = normalizado;
      return;
    }

    if (_lastEstadoProcesado == normalizado) return;
    _lastEstadoProcesado = normalizado;

    // Abre el modal de espera en 'en espera'. Las notificaciones locales por
    // cambio de estado ('en espera' → conductor afuera, 'en ruta' → viaje
    // iniciado) las dispara SolicitudEstadoController.handleEstadoCambio, y
    // funcionan en primer y segundo plano mientras el listener siga activo.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _estadoController.handleEstadoCambio(
        context: context,
        solicitudId: widget.solicitudId,
        estadoRaw: estado,
        onIrRutaClienteDestino: _goToRutaClienteDestino,
      );
    });
  }

  Future<void> _loadTaxiMarkerIcon() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      // Tamaño lógico fijo (~32x46) escalado por dpr → consistente y nítido en
      // todas las densidades (ni muy grande ni muy pequeño).
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(32, 46), devicePixelRatio: dpr),
        'assets/img/taxi_icon.png',
      );

      if (!mounted) return;
      setState(() {
        _taxiMarkerIcon = icon;
      });
    } catch (_) {}
  }

  void _syncSolicitudPersistence(TripTrackingViewModel vm) {
    final estado = vm.solicitud?.estado;
    if (estado == null || estado.trim().isEmpty) return;

    final normalizado = SolicitudEstadoController.normalizeEstado(estado);
    if (_lastPersistedStatus == normalizado) return;
    _lastPersistedStatus = normalizado;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_shouldPersistSolicitud(normalizado)) {
        try {
          await SessionHelper.setActiveSolicitud(widget.solicitudId);
          await RouteCacheService.saveForSolicitud(
            RouteCacheData(
              solicitudId: widget.solicitudId,
              role: 'cliente',
              clientName: vm.nombreUsuarioCard,
              clientLat: vm.clienteLatLng?.latitude,
              clientLng: vm.clienteLatLng?.longitude,
            ),
          );
        } catch (_) {}
        return;
      }

      if (_shouldClearSolicitud(normalizado)) {
        try {
          await SessionHelper.clearActiveSolicitud();
          await RouteCacheService.clearSolicitud(widget.solicitudId);
        } catch (_) {}
      }
    });
  }

  bool _shouldPersistSolicitud(String status) {
    return SolicitudEstado.isSesionActiva(status);
  }

  bool _shouldClearSolicitud(String status) {
    return SolicitudEstado.isTerminal(status);
  }

  Future<void> _goToRutaClienteDestino() async {
    if (_rutaDestinoNavigationDone || !mounted) return;
    _rutaDestinoNavigationDone = true;
    // Mark the intended screen so reloads will open RutaClienteDestino
    try {
      await SessionHelper.setActiveSolicitudScreen('ruta_cliente_destino');
    } catch (_) {}

    await navigateWithIntermediateLoader(
      context: context,
      nextBuilder: (_) => RutaClienteDestino(idSolicitud: widget.solicitudId),
      title: 'Viajando hacia el destino',
      subtitle: 'Tu viaje está en curso.',
      icon: Icons.navigation_rounded,
      accentColor: AppColores.buttonPrimary,
      drawCheck: false,
      delay: const Duration(milliseconds: 1500),
    );
  }

  Future<bool> _confirmarCancelacion() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColores.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel_outlined,
                  color: AppColores.error,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '¿Seguro quieres cancelar?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Se cancelará tu solicitud de viaje. Esta acción no se puede deshacer.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColores.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColores.textPrimary,
                        side: const BorderSide(color: AppColores.borderSubtle),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'No, seguir',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColores.error,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Sí, cancelar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return r == true;
  }

  Future<void> _onCancelPressed(TripTrackingViewModel vm) async {
    if (_cancelledNavigationDone || vm.isCancelling) return;

    if (!await _confirmarCancelacion() || !mounted) return;

    Object? cancelError;
    try {
      await vm.cancelSolicitud();
    } catch (error) {
      cancelError = error;
    }

    // After attempting cancel, verify remote state and delete the solicitud
    // from Firestore if it is actually cancelled.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(widget.solicitudId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final estadoRaw = (data?['status'] ?? data?['estado'] ?? '').toString();
        final estadoNorm = SolicitudEstadoController.normalizeEstado(estadoRaw);
        if (estadoNorm == SolicitudEstado.cancelado ||
            estadoNorm == SolicitudEstado.sinRespuesta) {
          try {
            await FirebaseFirestore.instance
                .collection('solicitudes')
                .doc(widget.solicitudId)
                .delete();
          } catch (_) {}

          try {
            await SessionHelper.clearActiveSolicitud();
          } catch (_) {}
          try {
            await RouteCacheService.clearSolicitud(widget.solicitudId);
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (!mounted) return;
    _navigateCancelado();

    if (cancelError != null) {
      debugPrint(
        '[TripTrackingScreen] Cancelacion remota pendiente por error: $cancelError',
      );
    }
  }

  /// Navega a InicioCliente mostrando la pantalla intermedia "Servicio
  /// cancelado" (animación de cancelación rápida y fluida). Es el único punto
  /// de salida cuando la solicitud queda en estado cancelado, sin importar si
  /// la canceló el cliente o el conductor.
  void _navigateCancelado() {
    if (_cancelledNavigationDone || !mounted) return;
    _cancelledNavigationDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await SessionHelper.clearActiveSolicitud();
        try {
          await SessionHelper.clearActiveSolicitudScreen();
        } catch (_) {}
        await RouteCacheService.clearSolicitud(widget.solicitudId);
      } catch (_) {}
      if (!mounted) return;
      await navigateWithIntermediateLoader(
        context: context,
        nextBuilder: (_) => const InicioClienteView(),
        title: 'Servicio cancelado',
        subtitle: 'Tu servicio fue cancelado.',
        icon: Icons.close_rounded,
        accentColor: AppColores.error,
        drawCheck: false,
        delay: const Duration(milliseconds: 1600),
        clearStackOnNext: true,
      );
    });
  }

  Future<void> _openChat(TripTrackingViewModel vm) async {
    await vm.markChatAsRead();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: const TripChatScreen(),
        ),
      ),
    );

    await vm.markChatAsRead();
  }

  Future<void> _toggleFocus(TripTrackingViewModel vm) async {
    final map = _mapController;
    if (map == null) return;

    if (vm.focusMode == MapFocusMode.clientOnly) {
      final persp = vm.getCameraPerspective();
      if (persp != null) {
        await map.animateCamera(CameraUpdate.newCameraPosition(persp));
      } else {
        final target = vm.clienteLatLng;
        if (target != null) {
          await map.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
        }
      }
      await vm.toggleMapFocusMode();
      return;
    }

    final a = vm.clienteLatLng;
    final b = vm.conductorLatLng;
    if (a != null && b != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          a.latitude < b.latitude ? a.latitude : b.latitude,
          a.longitude < b.longitude ? a.longitude : b.longitude,
        ),
        northeast: LatLng(
          a.latitude > b.latitude ? a.latitude : b.latitude,
          a.longitude > b.longitude ? a.longitude : b.longitude,
        ),
      );
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    await vm.toggleMapFocusMode();
  }

  void _fitInitialCameraIfNeeded(TripTrackingViewModel vm) {
    final map = _mapController;
    if (_initialCameraApplied || map == null) return;

    final a = vm.clienteLatLng;
    final b = vm.conductorLatLng;
    if (a == null || b == null) return;

    _initialCameraApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final persp = vm.getCameraPerspective();
      if (persp != null) {
        await map.animateCamera(CameraUpdate.newCameraPosition(persp));
      } else {
        final bounds = LatLngBounds(
          southwest: LatLng(
            a.latitude < b.latitude ? a.latitude : b.latitude,
            a.longitude < b.longitude ? a.longitude : b.longitude,
          ),
          northeast: LatLng(
            a.latitude > b.latitude ? a.latitude : b.latitude,
            a.longitude > b.longitude ? a.longitude : b.longitude,
          ),
        );
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      }
    });
  }

  void _handleSolicitudCanceladaIfNeeded(TripTrackingViewModel vm) {
    if (_cancelledNavigationDone) return;
    final estadoRaw = vm.solicitud?.estado;
    if (estadoRaw == null || estadoRaw.isEmpty) return;

    final estadoNormalizado = SolicitudEstadoController.normalizeEstado(
      estadoRaw,
    );
    if (estadoNormalizado != SolicitudEstado.cancelado &&
        estadoNormalizado != SolicitudEstado.sinRespuesta) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigateCancelado();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    try {
      _estadoController.waitModalVisible.removeListener(() {});
    } catch (_) {}
    _estadoController.dispose();
    _cancelDisableTimer?.cancel();
    super.dispose();
  }
}
