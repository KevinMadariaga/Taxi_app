import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
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
import 'package:taxi_app/widgets/preview_solicitud_card.dart';
import 'package:taxi_app/widgets/solicitud_card.dart';

class InicioConductor extends StatefulWidget {
  const InicioConductor({Key? key}) : super(key: key);

  @override
  State<InicioConductor> createState() => _InicioConductorState();
}

class _InicioConductorState extends State<InicioConductor>
    with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  int _selectedIndex = 1;
  bool _hasCentered = false;
  bool _navigatingToRuta = false;
  bool _gpsPromptShown = false;
  bool _isGpsDialogOpen = false;
  bool _isRequestingPermissions = false;
  bool _isPreparingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    final backgroundGranted =
        await PermissionsHelper.requestBackgroundLocationPermission();
    if (!backgroundGranted) {
      _showGpsSnackBar('Permiso de ubicación en segundo plano rechazado.');
      return false;
    }

    // 3) Todos los permisos OK: listos para iniciar.
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

      // Después de activar GPS y permisos en primer plano, solicitar permiso de ubicación en segundo plano para conductor.
      final bgGranted =
          await PermissionsHelper.requestBackgroundLocationPermission();
      if (!bgGranted) {
        _showGpsSnackBar(
          'Permiso de ubicación en segundo plano no concedido. Activar para un mejor seguimiento.',
        );
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
          // fire-and-forget permission request
          () async {
            try {
              await PermissionsHelper.requestAllPermissions(isDriver: true);
            } catch (_) {}
          }();

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

          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: AppColores.background,
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
                                                                      await _closePreview(vm);
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
                              return PreviewSolicitudCard(
                                preview: preview,
                                clientPhotoUrl: foto,
                                isLoading: _navigatingToRuta,
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
                                  final id = preview.solicitud.id;
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  try {
                                    await vm.aceptarSolicitud(id);
                                    await _navegarARutaConductor(vm, id);
                                  } catch (e) {
                                    if (mounted) {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _abrirContraofertaModal(
    InicioConductorViewmodel vm,
    PreviewSolicitud preview,
  ) async {
    final valorBase = (preview.valorServicio ?? 0).round();
    final initial = valorBase > 0 ? valorBase.toString() : '11000';
    final controller = TextEditingController(text: initial);

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
                    'Oferta actual del cliente: \$$valorBase',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      prefixText: '\$ ',
                      hintText: 'Ej: 11000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Contraoferta enviada. Esperando respuesta del cliente.',
                              ),
                            ),
                          );
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
