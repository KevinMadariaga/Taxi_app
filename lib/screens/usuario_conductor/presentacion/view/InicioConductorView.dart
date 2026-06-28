import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/navigation/inicio_conductor_navigation.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/InicioConductorViewModel.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/widgets/preview_solicitud_card.dart';
import 'package:taxi_app/widgets/solicitud_card.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/activacion_servicio_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';

class InicioConductor extends StatefulWidget {
  const InicioConductor({Key? key, this.mostrarBienvenida = false})
    : super(key: key);

  final bool mostrarBienvenida;

  @override
  State<InicioConductor> createState() => _InicioConductorState();
}

class _InicioConductorState extends State<InicioConductor>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  int _selectedIndex = 1;
  bool _hasCentered = false;
  bool _navigatingToRuta = false;
  bool _isAcceptingRequest = false;
  bool _gpsPromptShown = false;
  bool _isGpsDialogOpen = false;
  bool _isRequestingPermissions = false;
  bool _isPreparingLocation = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _membresiaSub;
  Timer? _membresiaExpiryTimer;
  bool _expirandoMembresia = false;
  bool _dialogMembresiaVisible = false;
  // null = primer snapshot aún no recibido; false = inactiva; true = activa
  bool? _membresiaPreviamenteActiva;

  // Mide la altura real de la card de preview para: (1) que el mapa reciba ese
  // padding inferior y centre los marcadores en la zona visible, y (2) que la
  // card use solo el alto de su contenido (sin hueco bajo los botones).
  final GlobalKey _previewCardKey = GlobalKey();
  double _previewCardHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initMembresiaWatcher();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ready = await _validateGpsAndPermissionsOnStart();
      if (!ready) return;

      if (mounted) {
        setState(() {
          _isPreparingLocation = true;
        });
      }

      await _bootstrapConductorLocationFlow();

      if (mounted) {
        setState(() {
          _isPreparingLocation = false;
        });
      }
    });
  }

  // Centraliza el cierre/retroceso de la preview para poder invocarlo
  // desde el listener cuando la solicitud cambie a cancelada.
  Future<void> _closePreview(InicioConductorViewmodel vm) async {
    await vm.stopPreviewSolicitudStatusListener();
    if (!mounted) return;
    vm.clearPreviewAndRoutes();
    if (vm.currentLocation != null) {
      try {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(vm.currentLocation!, 16),
        );
      } catch (_) {}
    }
  }

  Future<void> _bootstrapConductorLocationFlow() async {
    final ready = await _ensureLocationServiceAndPermission();
    if (!ready) return;
    await _requestAndCenterCurrentLocation();

    // Establecer la escucha de solicitudes para asegurar que responde a preview correctamente.
    try {
      final vm = Provider.of<InicioConductorViewmodel>(context, listen: false);
      vm.ensureSolicitudesSubscription();
    } catch (_) {}
  }

  Future<bool> _validateGpsAndPermissionsOnStart() async {
    if (!mounted) return false;

    // 1) Verificar GPS
    bool serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();
    if (!serviceEnabled) {
      final shouldOpen = await _showGpsDisabledDialog();
      if (shouldOpen) {
        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(milliseconds: 800));
        serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();
      }
    }

    if (!serviceEnabled) {
      _showGpsSnackBar('GPS no está activo. Abra ajustes y actívelo.');
      return false;
    }

    // 2) Validar permisos foreground y background
    final foregroundGranted =
        await PermissionsHelper.requestLocationPermission();
    if (!foregroundGranted) {
      _showGpsSnackBar('Permiso de ubicación primer plano denegado.');
      return false;
    }

    // 3) Permiso de segundo plano: mostrar explicación si aún no está concedido.
    final yaConBg = await PermissionsHelper.hasBackgroundLocationPermission();
    if (!yaConBg) {
      if (!mounted) return false;
      final continuar = await _showBackgroundLocationDialog();
      if (!continuar) {
        _showGpsSnackBar(
          'Activa la ubicación en segundo plano para recibir solicitudes.',
        );
        return false;
      }
    }

    final backgroundGranted =
        await PermissionsHelper.requestBackgroundLocationPermission();
    if (!backgroundGranted) {
      if (!mounted) return false;
      // En iOS el usuario puede haber elegido "Cuando uso la app" en vez de
      // "Siempre". Guiar a Ajustes para completar la selección.
      await _showIrAAjustesUbicacionDialog();
      return false;
    }

    // 4) Todos los permisos OK: listos para iniciar.
    return true;
  }

  Future<bool> _ensureLocationServiceAndPermission() async {
    if (!mounted) return false;
    if (_isRequestingPermissions) return false;

    _isRequestingPermissions = true;
    try {
      bool serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final shouldOpenSettings = await _showGpsDisabledDialog();
        if (!shouldOpenSettings) {
          _gpsPromptShown = true;
          _showGpsSnackBar('GPS no está activo. Actívelo para continuar.');
          return false;
        }

        await Geolocator.openLocationSettings();
        await Future.delayed(const Duration(milliseconds: 800));
        serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();
      }

      if (!serviceEnabled) {
        _gpsPromptShown = true;
        _showGpsSnackBar('GPS no está activo. Actívelo para continuar.');
        return false;
      }

      _gpsPromptShown = false;

      final hasPermission = await PermissionsHelper.hasLocationPermission();
      if (!hasPermission) {
        final shouldRequest = await _showRequestLocationPermissionDialog();
        if (!shouldRequest) return false;

        final granted = await PermissionsHelper.requestLocationPermission();
        if (!granted) {
          _showGpsSnackBar('Permiso de ubicación no concedido.');
          return false;
        }
      }

      // Permiso de segundo plano: mostrar explicación si aún no está concedido.
      final yaConBg = await PermissionsHelper.hasBackgroundLocationPermission();
      if (!yaConBg) {
        if (!mounted) return false;
        final continuar = await _showBackgroundLocationDialog();
        if (!continuar) {
          _showGpsSnackBar(
            'Activa la ubicación en segundo plano para recibir solicitudes.',
          );
          return false;
        }
      }

      final bgGranted =
          await PermissionsHelper.requestBackgroundLocationPermission();
      if (!bgGranted) {
        if (!mounted) return false;
        await _showIrAAjustesUbicacionDialog();
        return false;
      }

      return true;
    } finally {
      _isRequestingPermissions = false;
    }
  }

  // Centrar la cámara en la perspectiva del conductor hacia el cliente al seleccionar una solicitud
  Future<void> _centerPreviewOnConductorToClient(
    InicioConductorViewmodel vm,
    PreviewSolicitud preview,
  ) async {
    if (_mapController == null) return;
    final s = preview.solicitud;
    final client = LatLng(
      s.ubicacionInicial.latitude,
      s.ubicacionInicial.longitude,
    );
    final driver = vm.currentLocation;
    if (driver != null) {
      final bearing = vm.calculateBearing(driver, client);
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: driver, zoom: 16, bearing: bearing, tilt: 0),
        ),
      );
    } else {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(client, 16),
      );
    }
  }

  Future<void> _navegarARutaConductor(
    InicioConductorViewmodel vm,
    String solicitudId,
  ) async {
    if (_navigatingToRuta) {
      return;
    }

    if (mounted) {
      setState(() {
        _navigatingToRuta = true;
      });
    } else {
      _navigatingToRuta = true;
    }

    try {
      await _closePreview(vm);
      if (!mounted) {
        return;
      }
      await InicioConductorNavigation.irARutaConductor(context, solicitudId);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _navigatingToRuta = false;
        });
      } else {
        _navigatingToRuta = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InicioConductorViewmodel>(
      create: (context) {
        final vm = InicioConductorViewmodel();
        // Request necessary permissions and initialize services without blocking UI
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // fire-and-forget notification init
          () async {
            try {
              await NotificacionesServicio.instance.init();
            } catch (_) {}
          }();

          // Start viewmodel initialization in background so UI isn't blocked
          unawaited(vm.init());
        });
        return vm;
      },
      child: Consumer<InicioConductorViewmodel>(
        builder: (context, vm, _) {
          // Navega a la ruta cuando una solicitud queda asignada a este
          // conductor (acepta él o el cliente acepta su contraoferta),
          // escuchando el cambio de estado aunque no tenga la preview abierta.
          vm.onAsignadoAMi ??= (solicitudId) {
            if (!mounted || _navigatingToRuta) return;
            _navegarARutaConductor(vm, solicitudId);
          };
          if (_isPreparingLocation) {
            return const Scaffold(
              backgroundColor: AppColores.background,
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Preparando ubicación...',
                        style: TextStyle(
                          color: AppColores.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (vm.isLoading) {
            return const Scaffold(
              backgroundColor: AppColores.background,
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Cargando panel del conductor...',
                        style: TextStyle(
                          color: AppColores.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Si ya tenemos controlador y ubicación, centrar el mapa una sola vez.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_hasCentered &&
                _mapController != null &&
                vm.currentLocation != null) {
              _hasCentered = true;
              vm.centerMapOnMarker(
                _mapController!,
                zoom: vm.currentLocation != null ? 16.0 : 14.5,
              );
            }
          });

          final selectedPreview = vm.isConnected ? vm.selectedPreview : null;
          final bool previewVisible = vm.isConnected && vm.selectedPreview != null;
          // Padding inferior del mapa = alto real de la card (medido). Hasta
          // medir, se usa un estimado (~42%) para evitar saltos grandes.
          final double mapBottomPadding = _previewCardHeight > 0
              ? _previewCardHeight
              : MediaQuery.of(context).size.height * 0.42;

          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: AppColores.background,
              resizeToAvoidBottomInset: false,
              appBar: previewVisible
                  ? null
                  : AppBar(
                      backgroundColor: AppColores.background,
                      foregroundColor: AppColores.textPrimary,
                      elevation: 0,
                      automaticallyImplyLeading: false,
                    ),
              body: SafeArea(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      children: [
                        // Nombre y placa arriba (dentro de un marco) -- ocultar cuando hay preview seleccionada
                        if (vm.selectedPreview == null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16.0,
                              0.0,
                              16.0,
                              8.0,
                            ),
                            child: Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(minHeight: 110),
                              decoration: BoxDecoration(
                                color: AppColores.cardBackground,
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(
                                  color: AppColores.borderSubtle,
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColores.borderSubtle,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),

                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 14.0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          vm.displayName.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: AppColores.textPrimary,
                                          ),
                                        ),

                                        const SizedBox(height: 10.0),
                                        // Estrellas de calificación desde el ViewModel
                                        Builder(
                                          builder: (ctx) {
                                            final double promedio = vm.rating
                                                .clamp(0.0, 5.0)
                                                .toDouble();

                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children:
                                                      List.generate(5, (index) {
                                                          final icon =
                                                              promedio >=
                                                                  index + 1
                                                              ? Icons.star
                                                              : (promedio >=
                                                                        index +
                                                                            0.5
                                                                    ? Icons
                                                                          .star_half
                                                                    : Icons
                                                                          .star_border);
                                                          return Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  right: 4,
                                                                ),
                                                            child: Icon(
                                                              icon,
                                                              color:
                                                                  icon ==
                                                                      Icons
                                                                          .star_border
                                                                  ? AppColores
                                                                        .grey400
                                                                  : AppColores
                                                                        .primary,
                                                              size: 18,
                                                            ),
                                                          );
                                                        })
                                                        ..add(
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                        )
                                                        ..add(
                                                          Text(
                                                            promedio
                                                                .toStringAsFixed(
                                                                  1,
                                                                ),
                                                            style: const TextStyle(
                                                              color: AppColores
                                                                  .textPrimary,
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                          ),
                                                        )
                                                        ..add(
                                                          const Text(
                                                            '/5.0',
                                                            style: TextStyle(
                                                              color: AppColores
                                                                  .textSecondary,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  vm.totalRatings > 0
                                                      ? 'Basado en ${vm.totalRatings} calificaciones de clientes'
                                                      : 'Aun sin calificaciones de clientes',
                                                  style: const TextStyle(
                                                    color: AppColores
                                                        .textSecondary,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12.0),
                                  // Foto circular del conductor desde el ViewModel
                                  Builder(
                                    builder: (ctx) {
                                      String photoUrl = vm.photoUrl ?? '';

                                      if (photoUrl.isNotEmpty) {
                                        return ClipOval(
                                          child: Image.network(
                                            photoUrl,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx2, error, stack) {
                                              return Container(
                                                width: 100,
                                                height: 100,
                                                decoration: const BoxDecoration(
                                                  color: AppColores.grey200,
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  vm.displayName.isNotEmpty
                                                      ? vm.displayName
                                                            .trim()[0]
                                                            .toUpperCase()
                                                      : 'C',
                                                  style: const TextStyle(
                                                    fontSize: 40,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        AppColores.textPrimary,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      }

                                      return Container(
                                        width: 100,
                                        height: 100,
                                        decoration: const BoxDecoration(
                                          color: AppColores.grey200,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          vm.displayName.isNotEmpty
                                              ? vm.displayName
                                                    .trim()[0]
                                                    .toUpperCase()
                                              : 'C',
                                          style: const TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: AppColores.textPrimary,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Espacio entre la tarjeta de información del conductor y el mapa
                        const SizedBox(height: 12),

                        // Mapa colocado justo bajo el contenedor de información y ocupa el espacio restante
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10.0,
                              vertical: 7.0,
                            ),
                            child: Container(
                              height: double.infinity,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: vm.selectedPreview == null
                                    ? AppColores.cardBackground
                                    : Colors.transparent,
                                borderRadius: vm.selectedPreview == null
                                    ? BorderRadius.circular(12)
                                    : BorderRadius.zero,
                                border: Border.all(
                                  color: AppColores.borderSubtle,
                                  width: 1.2,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: vm.selectedPreview == null
                                        ? BorderRadius.circular(12)
                                        : BorderRadius.zero,
                                    child: Builder(
                                      builder: (context) {
                                        final markers = <Marker>{};
                                        final polylines = <Polyline>{};
                                        // We use the map's default my-location blue dot (`myLocationEnabled`) instead
                                        // of adding a custom driver marker to avoid duplicate/red markers.
                                        final preview = vm.selectedPreview;
                                        if (preview != null) {
                                          final s = preview.solicitud;
                                          final clientPos = LatLng(
                                            s.ubicacionInicial.latitude,
                                            s.ubicacionInicial.longitude,
                                          );
                                          markers.add(
                                            Marker(
                                              markerId: MarkerId(
                                                'client_${s.id}',
                                              ),
                                              position: clientPos,
                                              infoWindow: InfoWindow(
                                                title:
                                                    s.nombreCliente ??
                                                    'Cliente',
                                                snippet: s.direccion,
                                              ),
                                            ),
                                          );
                                          if (vm.currentLocation != null) {
                                            final hasRouted = vm.routePolylines
                                                .any(
                                                  (p) =>
                                                      p.polylineId.value ==
                                                      'route_${s.id}',
                                                );
                                            if (!hasRouted) {
                                              polylines.add(
                                                Polyline(
                                                  polylineId: PolylineId(
                                                    'route_${s.id}',
                                                  ),
                                                  points: [
                                                    vm.currentLocation!,
                                                    clientPos,
                                                  ],
                                                  color: AppColores.primary,
                                                  width: 4,
                                                ),
                                              );
                                            }
                                          }
                                        }

                                        return AppGoogleMap(
                                          initialTarget:
                                              vm.currentLocation ??
                                              const LatLng(
                                                8.2595534,
                                                -73.353469,
                                              ),
                                          initialZoom:
                                              vm.currentLocation != null
                                              ? 16.0
                                              : 14.5,
                                          // Deja libre el alto de la card para
                                          // centrar los marcadores arriba.
                                          padding: previewVisible
                                              ? EdgeInsets.only(
                                                  bottom: mapBottomPadding,
                                                )
                                              : EdgeInsets.zero,
                                          myLocationEnabled: true,
                                          myLocationButtonEnabled: true,
                                          compassEnabled: true,
                                          rotateGesturesEnabled: true,
                                          tiltGesturesEnabled: false,
                                          markers: markers.union(
                                            vm.extraMarkers,
                                          ),
                                          polylines: polylines.union(
                                            vm.routePolylines,
                                          ),
                                          circles: vm.currentLocation != null
                                              ? {
                                                  Circle(
                                                    circleId: const CircleId(
                                                      'driver_radius',
                                                    ),
                                                    center: vm.currentLocation!,
                                                    radius: 3000, // meters
                                                    strokeWidth: 2,
                                                    strokeColor: AppColores
                                                        .primary
                                                        .withValues(alpha: 0.7),
                                                    fillColor: AppColores
                                                        .primary
                                                        .withValues(alpha: 0.06),
                                                  ),
                                                }
                                              : const <Circle>{},
                                          onMapCreated: (controller) async {
                                            _mapController = controller;

                                            // If driver location is already available, center map.
                                            if (vm.currentLocation != null) {
                                              if (preview != null) {
                                                final driver =
                                                    vm.currentLocation!;
                                                final client = LatLng(
                                                  preview
                                                      .solicitud
                                                      .ubicacionInicial
                                                      .latitude,
                                                  preview
                                                      .solicitud
                                                      .ubicacionInicial
                                                      .longitude,
                                                );
                                                final bearing = vm
                                                    .calculateBearing(
                                                      driver,
                                                      client,
                                                    );
                                                await _mapController!.animateCamera(
                                                  CameraUpdate.newCameraPosition(
                                                    CameraPosition(
                                                      target: driver,
                                                      zoom: 16,
                                                      bearing: bearing,
                                                      tilt: 0,
                                                    ),
                                                  ),
                                                );
                                              } else if (!_hasCentered) {
                                                _hasCentered = true;
                                                await vm.centerMapOnMarker(
                                                  _mapController!,
                                                  zoom: 16.0,
                                                );
                                              }
                                            }
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  if (vm.isLoadingPreviewRoute)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(
                                                color: AppColores.primary,
                                              ),
                                              SizedBox(height: 12),
                                              Text(
                                                'Cargando ruta...',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                  // Lista de solicitudes flotante encima del mapa (apiladas verticalmente)
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    right: 12,
                                    child: Builder(
                                      builder: (context) {
                                        final sols = vm.solicitudes;
                                        if (!vm.isConnected || sols.isEmpty)
                                          return const SizedBox.shrink();

                                        return Align(
                                          alignment: Alignment.topCenter,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Encabezado único
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColores.error,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColores
                                                          .borderSubtle,
                                                      blurRadius: 2,
                                                      offset: const Offset(
                                                        0,
                                                        1,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: const Text(
                                                  'Solicitud pendiente',
                                                  style: TextStyle(
                                                    color: AppColores.textWhite,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),

                                              // Contenedor desplazable con máximo alto para no tapar todo el mapa
                                              if (vm.isConnected &&
                                                  vm.selectedPreview == null)
                                                ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    maxHeight:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.height *
                                                        0.45,
                                                  ),
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: List.generate(sols.length, (
                                                        i,
                                                      ) {
                                                        final s = sols[i];
                                                        return Padding(
                                                          padding: EdgeInsets.only(
                                                            bottom:
                                                                i ==
                                                                    sols.length -
                                                                        1
                                                                ? 0
                                                                : 8,
                                                          ),
                                                          child: SizedBox(
                                                            width:
                                                                MediaQuery.of(
                                                                  context,
                                                                ).size.width *
                                                                0.92,
                                                            child: SolicitudCard(
                                                              solicitud: s,
                                                              expanded: false,
                                                              onTap: (preview) {
                                                                final s = preview.solicitud;
                                                                // selectPreview llama internamente a preloadClientePhoto
                                                                vm.selectPreview(preview);

                                                                // Iniciar listener sin bloquear la animación de la card
                                                                unawaited(
                                                                  vm.listenPreviewSolicitudStatus(
                                                                    solicitudId: s.id,
                                                                    onCanceladoOrRemoved: () async {
                                                                      if (!mounted) return;
                                                                      // Estaba en la preview: cerrarla y avisar con snackbar,
                                                                      // permaneciendo en el mapa para seguir recibiendo solicitudes.
                                                                      await _closePreview(vm);
                                                                      if (!mounted) return;
                                                                      ScaffoldMessenger.of(context)
                                                                          .showSnackBar(
                                                                        const SnackBar(
                                                                          content: Text(
                                                                            'El cliente canceló la solicitud.',
                                                                          ),
                                                                          backgroundColor:
                                                                              AppColores.error,
                                                                        ),
                                                                      );
                                                                    },
                                                                    onAsignado: () async {
                                                                      await _navegarARutaConductor(vm, s.id);
                                                                    },
                                                                  ),
                                                                );

                                                                // Animar cámara sin await para no bloquear la UI
                                                                if (vm.currentLocation != null) {
                                                                  final driver = vm.currentLocation!;
                                                                  final client = LatLng(
                                                                    s.ubicacionInicial.latitude,
                                                                    s.ubicacionInicial.longitude,
                                                                  );
                                                                  unawaited(_centerPreviewOnConductorToClient(vm, preview));
                                                                  vm.fetchRouteOSRM(s.id, driver, client);
                                                                } else {
                                                                  unawaited(
                                                                    _mapController?.animateCamera(
                                                                      CameraUpdate.newLatLngZoom(
                                                                        LatLng(
                                                                          s.ubicacionInicial.latitude,
                                                                          s.ubicacionInicial.longitude,
                                                                        ),
                                                                        16,
                                                                      ),
                                                                    ),
                                                                  );
                                                                }
                                                              },
                                                            ),
                                                          ),
                                                        );
                                                      }),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Botón de conexión colocado debajo del mapa, ancho completo
                        if (!vm.isMapExpanded && vm.selectedPreview == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 16.0,
                            ),
                            child: Builder(
                              builder: (ctx) {
                                final connected = vm.isConnected;
                                return SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton.icon(
                                    onPressed: vm.isTogglingConnection
                                        ? null
                                        : vm.toggleConductorConnection,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: connected
                                          ? AppColores.buttonPrimary
                                          : AppColores.grey400,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: vm.isTogglingConnection
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColores.textWhite,
                                            ),
                                          )
                                        : Icon(
                                            connected
                                                ? Icons.toggle_on
                                                : Icons.toggle_off,
                                            size: 28,
                                          ),
                                    label: Text(
                                      connected ? 'Conectado' : 'Desconectado',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    // Preview card deslizable desde el fondo (patrón Uber/Bolt)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        offset: previewVisible
                            ? Offset.zero
                            : const Offset(0, 1),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          opacity: previewVisible ? 1.0 : 0.0,
                          child: Builder(
                            builder: (ctx) {
                              final preview = selectedPreview;
                              if (!previewVisible || preview == null) {
                                return const SizedBox.shrink();
                              }
                              final foto =
                                  preview.solicitud.clienteFoto?.isNotEmpty ==
                                      true
                                  ? preview.solicitud.clienteFoto
                                  : vm.fotoClientePorId(
                                      preview.solicitud.clienteId,
                                    );
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final h = _previewCardKey.currentContext?.size
                                    ?.height;
                                if (mounted &&
                                    h != null &&
                                    h > 0 &&
                                    (h - _previewCardHeight).abs() > 1) {
                                  setState(() => _previewCardHeight = h);
                                }
                              });
                              return Container(
                                key: _previewCardKey,
                                child: PreviewSolicitudCard(
                                preview: preview,
                                clientPhotoUrl: foto,
                                isAcceptLoading: _isAcceptingRequest,
                                onClose: () async {
                                  if (!_navigatingToRuta) {
                                    await _closePreview(vm);
                                  }
                                },
                                onCancel: () async {
                                  if (!_navigatingToRuta) {
                                    await _closePreview(vm);
                                  }
                                },
                                onAccept: () async {
                                  if (_isAcceptingRequest || _navigatingToRuta) return;
                                  setState(() => _isAcceptingRequest = true);
                                  final id = preview.solicitud.id;
                                  final messenger = ScaffoldMessenger.of(context);
                                  try {
                                    await vm.aceptarSolicitud(id);
                                    if (mounted) setState(() => _isAcceptingRequest = false);
                                    await _navegarARutaConductor(vm, id);
                                  } on StateError catch (e) {
                                    if (mounted) {
                                      setState(() => _isAcceptingRequest = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(e.message),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => _isAcceptingRequest = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error al aceptar servicio: $e',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                onCounterOffer: () async {
                                  if (!_navigatingToRuta) {
                                    await _abrirContraofertaModal(
                                      vm,
                                      preview,
                                    );
                                  }
                                },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // floatingActionButton removed — button is placed below the map in the Column
              bottomNavigationBar:
                  !vm.isMapExpanded && vm.selectedPreview == null
                  ? BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      selectedItemColor: AppColores.primary,
                      unselectedItemColor: AppColores.textSecondary,
                      items: const [
                        BottomNavigationBarItem(
                          icon: Icon(Icons.menu),
                          label: 'Mas opciones',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.map),
                          label: 'Mapa',
                        ),
                        BottomNavigationBarItem(
                          icon: Icon(Icons.person_outline),
                          label: 'Tú',
                        ),
                      ],
                      onTap: _onBottomNavTap,
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// Vigila la membresía del conductor en `usuarios/{uid}`. Mientras no esté
  /// `activa`, muestra el modal de activación (persistente). Cuando pasa a
  /// `activa`, lo cierra (y la pantalla de pago si estuviera encima).
  void _initMembresiaWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _membresiaSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          final data = doc.data();
          final flagActiva =
              (data?['membresia'] ?? '').toString().toLowerCase() == 'activa';
          final venceRaw = data?['membresiaVence'];
          final DateTime? vence = venceRaw is Timestamp
              ? venceRaw.toDate()
              : null;
          final now = DateTime.now();
          // Vencida = marcada activa pero ya pasó la fecha de vencimiento.
          final vencida = flagActiva && vence != null && !vence.isAfter(now);

          // El snapshot NO se re-dispara por el solo paso del tiempo: programa
          // un Timer que corte exactamente al vencer (ej. activada el 7 a las
          // 14:00 por 1 día → corta el 8 a las 14:00).
          _membresiaExpiryTimer?.cancel();
          if (flagActiva && vence != null && vence.isAfter(now)) {
            _membresiaExpiryTimer = Timer(
              vence.difference(now),
              () => _expirarMembresia(uid),
            );
          }

          // Si ya venció (incluido al reabrir la app tras el plazo), persiste la
          // desactivación; eso re-dispara el snapshot con membresia vacía.
          if (vencida) {
            _expirarMembresia(uid);
          }

          final activa = flagActiva && !vencida;

          if (!activa && !_dialogMembresiaVisible) {
            _dialogMembresiaVisible = true;
            mostrarBienvenidaConductorDialog(
              context,
              onVolverCliente: _volverACliente,
            ).whenComplete(() {
              _dialogMembresiaVisible = false;
            });
          } else if (activa) {
            if (_dialogMembresiaVisible) {
              _dialogMembresiaVisible = false;
              Navigator.of(context).popUntil((route) => route.isFirst);
            }

            // Detectar activación: primera apertura con mostrarBienvenida=true
            // (tap en notificación FCM) o transición inactivo → activo en vivo.
            final primeraVezActiva =
                _membresiaPreviamenteActiva == null && widget.mostrarBienvenida;
            final recienActivada = _membresiaPreviamenteActiva == false;

            if (primeraVezActiva || recienActivada) {
              if (recienActivada) {
                // Conductor tiene la app abierta en este momento: notificación local.
                NotificacionesServicio.instance.showNotification(
                  id: 'membresia_activada'.hashCode,
                  title: '¡Membresía activada!',
                  body:
                      'Tu membresía de conductor está activa. ¡Ya puedes recibir solicitudes!',
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _mostrarDialogBienvenidaActivacion();
              });
            }
          }

          _membresiaPreviamenteActiva = activa;
        });
  }

  /// Muestra explicación antes de pedir permiso de ubicación en segundo plano.
  /// Retorna true si el usuario acepta continuar, false si pospone.
  Future<bool> _showBackgroundLocationDialog() async {
    if (!mounted) return false;
    final bool isIOS = Platform.isIOS;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColores.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 38,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ubicación en segundo plano',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Para recibir solicitudes y compartir tu posición con los clientes '
              'mientras usas otras apps, necesitamos acceder a tu ubicación '
              'siempre, incluso en segundo plano.',
              style: const TextStyle(
                fontSize: 14,
                color: AppColores.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (isIOS) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColores.grey100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'En el diálogo que aparece a continuación, selecciona '
                  '"Siempre" para activar el seguimiento en segundo plano.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColores.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: AppColores.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Activar ubicación',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Recordar más tarde',
                  style: TextStyle(
                    color: AppColores.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return result == true;
  }

  /// Se muestra cuando el sistema denegó "siempre" (usuario eligió "cuando uso").
  /// Guía al conductor a Ajustes para cambiar manualmente la opción.
  Future<void> _showIrAAjustesUbicacionDialog() async {
    if (!mounted) return;
    final bool isIOS = Platform.isIOS;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColores.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 38,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Permiso insuficiente',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isIOS
                  ? 'Ve a Ajustes → Privacidad → Localización → Ride y selecciona "Siempre".'
                  : 'Ve a Ajustes → Aplicaciones → Ride → Permisos → Ubicación y selecciona "Permitir todo el tiempo".',
              style: const TextStyle(
                fontSize: 14,
                color: AppColores.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.buttonPrimary,
                foregroundColor: AppColores.textPrimary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await Geolocator.openAppSettings();
              },
              child: const Text(
                'Abrir Ajustes',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Después',
              style: TextStyle(
                color: AppColores.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogBienvenidaActivacion() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified, size: 64, color: AppColores.primary),
            SizedBox(height: 16),
            Text(
              '¡Membresía activada!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              'Bienvenido como conductor activo. Ya puedes conectarte y recibir solicitudes de viaje.',
              style: TextStyle(color: AppColores.textSecondary, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.buttonPrimary,
                foregroundColor: AppColores.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _iniciarFlujoUbicacionSiNecesario();
              },
              child: const Text(
                '¡Comenzar!',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Verifica permisos e inicia el flujo de ubicación. Se llama tras confirmar
  /// membresía activa para garantizar que los permisos se piden en el contexto
  /// correcto (especialmente el diálogo de "siempre" en iOS).
  Future<void> _iniciarFlujoUbicacionSiNecesario() async {
    final yaConBg = await PermissionsHelper.hasBackgroundLocationPermission();
    if (yaConBg) return; // permisos ya completos desde sesión anterior
    if (!mounted) return;
    final ready = await _validateGpsAndPermissionsOnStart();
    if (!ready || !mounted) return;
    setState(() => _isPreparingLocation = true);
    await _bootstrapConductorLocationFlow();
    if (mounted) setState(() => _isPreparingLocation = false);
  }

  /// Desactiva la membresía en Firestore al vencer el plazo (idempotente).
  /// Deja `membresia` vacía y `servicioActivo` en false, igual que una revocación
  /// del administrador, para que el conductor quede inactivo de inmediato.
  Future<void> _expirarMembresia(String uid) async {
    if (_expirandoMembresia) return;
    _expirandoMembresia = true;
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'membresia': '',
        'servicioActivo': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
    } finally {
      _expirandoMembresia = false;
    }
  }

  /// Vuelve a ser cliente desde la modal: cancela el watcher (para que no
  /// reaparezca), cambia el rol a cliente (fire-and-forget) y navega a
  /// InicioCliente removiendo la modal e InicioConductor.
  void _volverACliente() {
    _membresiaSub?.cancel();
    _membresiaSub = null;
    _membresiaExpiryTimer?.cancel();
    _membresiaExpiryTimer = null;
    _dialogMembresiaVisible = false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // rol cliente + quitar solicitud para retirar la notificación del admin.
      FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'rol': 'cliente',
        'solicitudConductor': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Sincronizar caché para que al reiniciar abra como cliente.
      SessionHelper.updateRole('cliente');
    }

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _membresiaSub?.cancel();
    _membresiaExpiryTimer?.cancel();
    _mapController = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleAppResumed() async {
    if (!mounted) return;

    if (_isGpsDialogOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      _isGpsDialogOpen = false;
    }

    bool serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();

    if (!serviceEnabled) {
      final shouldOpenSettings = await _showGpsDisabledDialog();
      if (!shouldOpenSettings) {
        _gpsPromptShown = true;
        _showGpsSnackBar('GPS no está activo. Actívelo para continuar.');
        return;
      }

      await Geolocator.openLocationSettings();
      await Future.delayed(const Duration(milliseconds: 800));
      serviceEnabled = await PermissionsHelper.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _gpsPromptShown = true;
        _showGpsSnackBar('GPS no está activo. Actívelo para continuar.');
        return;
      }
    }

    // Si llegamos con GPS activo, limpiar indicador y snackbar anterior.
    if (_gpsPromptShown) {
      _gpsPromptShown = false;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    final ready = await _ensureLocationServiceAndPermission();
    if (!ready) return;

    await _requestAndCenterCurrentLocation();

    // Reactivar suscripción de solicitudes si está conectado y no se estaba escuchando.
    try {
      final vm = Provider.of<InicioConductorViewmodel>(context, listen: false);
      vm.ensureSolicitudesSubscription();
    } catch (_) {
      // ignore if no provider available.
    }
  }

  Future<void> _requestAndCenterCurrentLocation() async {
    if (!mounted) return;

    InicioConductorViewmodel? vm;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final currentLocation = LatLng(position.latitude, position.longitude);

      // Actualiza VM si está disponible
      try {
        vm = Provider.of<InicioConductorViewmodel>(context, listen: false);
        vm.currentLocation = currentLocation;
      } catch (_) {
        // Puede ocurrir antes de que exista contexto del provider (según ciclo de vida)
      }

      await vm?.guardarUbicacionConectado(currentLocation);

      // Centrar en el mapa si tenemos ubicación válida.
      // Esto garantiza que cuando pase la pantalla de carga de ubicación,
      // el conductor quede centrado inmediatamente si ya hay mapa creado.
      if (_mapController != null) {
        try {
          if (vm != null) {
            await vm.centerMapOnMarker(_mapController!, zoom: 16.0);
          } else {
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: currentLocation, zoom: 16.0),
              ),
            );
          }
          _hasCentered = true;
        } catch (_) {
          try {
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: currentLocation, zoom: 16.0),
              ),
            );
            _hasCentered = true;
          } catch (_) {
            // Ignorar si no se puede centrar, pero persistimos location en VM.
          }
        }
      } else {
        // Si el mapa aún no está listo, el callback de onMapCreated se encargará de centrar.
        _hasCentered = false;
      }
    } catch (_) {
      // no hacemos crash, puede haber servicios desactivados/etc.
    }
  }

  void _showGpsSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _showGpsDisabledDialog() async {
    if (!mounted) return false;

    _isGpsDialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('GPS desactivado'),
          content: const Text(
            'El GPS está desactivado. Por favor actívelo para que la app pueda obtener su ubicación.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Activar'),
            ),
          ],
        );
      },
    );

    _isGpsDialogOpen = false;
    return result == true;
  }

  Future<bool> _showRequestLocationPermissionDialog() async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Permiso de ubicación'),
          content: const Text(
            'Necesitamos permiso de ubicación para mostrar su posición en el mapa. Por favor permita el permiso.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Permitir'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _navigateToPerfilConductor() {
    return InicioConductorNavigation.irAPerfilConductor(context);
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      await _showMoreOptionsSheet();
      if (!mounted) return;
      setState(() => _selectedIndex = 1);
    } else if (index == 2) {
      setState(() => _selectedIndex = 2);
      await _navigateToPerfilConductor();
      if (!mounted) return;
      setState(() => _selectedIndex = 1);
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _showMoreOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Seguridad'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irASeguridad(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Ayuda'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irAAyuda(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text('Soporte'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irASoporte(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('Notificaciones'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irANotificaciones(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.comment_outlined),
                title: const Text('Comentarios'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irAComentarios(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Historial'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irAHistorialConductor(
                    context,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _fmtMoneda(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final rev = s.length - i;
      buf.write(s[i]);
      if (rev > 1 && rev % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }

  /// Modal de confirmación que se cierra solo a los 3 segundos.
  void _mostrarConfirmacionContraoferta(int valor) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 3), () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  color: AppColores.success, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Contraoferta enviada',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                'Se hizo contraoferta de \$${_fmtMoneda(valor)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColores.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _abrirContraofertaModal(
    InicioConductorViewmodel vm,
    PreviewSolicitud preview,
  ) async {
    final valorBase = (preview.valorServicio ?? 0).round();
    final base = valorBase > 0 ? valorBase : 10000;
    final controller = TextEditingController();

    final opciones =
        <int>{base + 1000, base + 2000, base + 3000, base + 5000, base + 7000}
            .toList()
          ..sort();

    void setValor(int v) {
      final t = v.toString();
      controller.value = TextEditingValue(
        text: t,
        selection: TextSelection(baseOffset: 0, extentOffset: t.length),
      );
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
                    'Enviar contraoferta',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Oferta actual del cliente: \$${_fmtMoneda(valorBase)}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      hintText: 'Ej: 11000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: opciones
                        .map(
                          (o) => ActionChip(
                            label: Text('\$${_fmtMoneda(o)}'),
                            onPressed: () => setValor(o),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.buttonPrimary,
                        foregroundColor: AppColores.textWhite,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () async {
                        final digits = controller.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        if (digits.isEmpty) return;
                        final valor = double.tryParse(digits);
                        if (valor == null || valor <= 0) return;

                        try {
                          await vm.enviarContraoferta(
                            solicitudId: preview.solicitud.id,
                            nuevoValor: valor,
                          );
                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                          _mostrarConfirmacionContraoferta(valor.round());
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'No se pudo enviar la contraoferta: $e',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Enviar contraoferta'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
