import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/navigation/inicio_conductor_navigation.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/InicioConductorViewModel.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
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
  String? _lastFittedPreviewId;
  bool _hasCenteredForPreview = false;
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

  Future<void> _fitBoundsForPreview(
    PreviewSolicitud preview,
    InicioConductorViewmodel vm,
  ) async {
    if (_mapController == null) return;
    final s = preview.solicitud;
    final client = LatLng(
      s.ubicacionInicial.latitude,
      s.ubicacionInicial.longitude,
    );

    final points = <LatLng>[];
    if (vm.currentLocation != null) points.add(vm.currentLocation!);
    points.add(client);

    // Include all polyline points for accurate bounds
    for (final poly in vm.routePolylines) {
      try {
        points.addAll(poly.points);
      } catch (_) {}
    }

    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      // Use larger padding to ensure the full polyline is visible
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 120),
      );
      _hasCenteredForPreview = true;
    } catch (_) {
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(client, 15),
        );
        _hasCenteredForPreview = true;
      } catch (_) {}
    }
  }

  double get _previewHeight {
    final screenHeight = MediaQuery.of(context).size.height;
    final proposedHeight = screenHeight * 0.44;
    return proposedHeight.clamp(220.0, screenHeight * 0.45).toDouble();
  }

  bool _hasPreviewComment(PreviewSolicitud preview) {
    final raw = preview.comentarioCliente?.trim();
    if (raw == null || raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    return lower != 'null' &&
        lower != 'sin comentario' &&
        lower != 'ninguno' &&
        lower != 'n/a' &&
        lower != 'na' &&
        raw != '-';
  }

  double _previewHeightFor(PreviewSolicitud preview) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (_hasPreviewComment(preview)) {
      return _previewHeight;
    }

    final proposedHeight = screenHeight * 0.35;
    return proposedHeight.clamp(196.0, screenHeight * 0.38).toDouble();
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
              await NotificationService.instance.init();
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
          // If a preview is selected, attempt to fit bounds including polylines and markers.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final preview = vm.selectedPreview;
            if (preview != null) {
              final id = preview.solicitud.id;
              if (_lastFittedPreviewId != id) {
                _lastFittedPreviewId = id;
                _hasCenteredForPreview = false;
                _fitBoundsForPreview(preview, vm);
              } else if (!_hasCenteredForPreview &&
                  vm.routePolylines.isNotEmpty) {
                _fitBoundsForPreview(preview, vm);
              }
            } else {
              _lastFittedPreviewId = null;
              _hasCenteredForPreview = false;
            }
          });

          final selectedPreview = vm.isConnected ? vm.selectedPreview : null;
          final previewCardHeight = selectedPreview != null
              ? _previewHeightFor(selectedPreview)
              : _previewHeight;

          // Suscribirse una sola vez a cambios del nombre guardado en cache
          final bool _hasPreview = vm.isConnected && vm.selectedPreview != null;
          return WillPopScope(
            onWillPop: () async => false,
            child: Scaffold(
            backgroundColor: AppColores.background,
            appBar: _hasPreview
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
                                                mainAxisSize: MainAxisSize.min,
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
                                                                FontWeight.w800,
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
                                                                FontWeight.w600,
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
                                                  color:
                                                      AppColores.textSecondary,
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
                                                  color: AppColores.textPrimary,
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

                      // Mantener layout fijo: información arriba y mapa abajo.
                      if (vm.isConnected && vm.selectedPreview != null)
                        SizedBox(height: previewCardHeight),

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
                                                  s.nombreCliente ?? 'Cliente',
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
                                            const LatLng(8.2595534, -73.353469),
                                        initialZoom: vm.currentLocation != null
                                            ? 16.0
                                            : 14.5,
                                        myLocationEnabled: true,
                                        myLocationButtonEnabled: true,
                                        compassEnabled: true,
                                        rotateGesturesEnabled: true,
                                        tiltGesturesEnabled: false,
                                        markers: markers.union(vm.extraMarkers),
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
                                                      .withOpacity(0.7),
                                                  fillColor: AppColores.primary
                                                      .withOpacity(0.06),
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
                                                    color:
                                                        AppColores.borderSubtle,
                                                    blurRadius: 2,
                                                    offset: const Offset(0, 1),
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
                                                            onTap: (preview) async {
                                                              final s = preview
                                                                  .solicitud;
                                                              vm.selectPreview(
                                                                preview,
                                                              );
                                                              unawaited(
                                                                vm.preloadClientePhoto(
                                                                  s.clienteId,
                                                                ),
                                                              );

                                                              await vm.listenPreviewSolicitudStatus(
                                                                solicitudId:
                                                                    s.id,
                                                                onCanceladoOrRemoved:
                                                                    () async {
                                                                      if (!mounted) {
                                                                        return;
                                                                      }
                                                                      await _closePreview(
                                                                        vm,
                                                                      );
                                                                    },
                                                                onAsignado:
                                                                    () async {
                                                                      await _navegarARutaConductor(
                                                                        vm,
                                                                        s.id,
                                                                      );
                                                                    },
                                                              );

                                                              if (vm.currentLocation !=
                                                                  null) {
                                                                final driver = vm
                                                                    .currentLocation!;
                                                                final client = LatLng(
                                                                  s
                                                                      .ubicacionInicial
                                                                      .latitude,
                                                                  s
                                                                      .ubicacionInicial
                                                                      .longitude,
                                                                );
                                                                await _centerPreviewOnConductorToClient(
                                                                  vm,
                                                                  preview,
                                                                );
                                                                // Try to fetch a routed polyline (OSRM) for mejor trazabilidad
                                                                vm.fetchRouteOSRM(
                                                                  s.id,
                                                                  driver,
                                                                  client,
                                                                );
                                                              } else {
                                                                await _mapController?.animateCamera(
                                                                  CameraUpdate.newLatLngZoom(
                                                                    LatLng(
                                                                      s
                                                                          .ubicacionInicial
                                                                          .latitude,
                                                                      s
                                                                          .ubicacionInicial
                                                                          .longitude,
                                                                    ),
                                                                    16,
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
                  // Selected solicitud preview: in-flow so the map appears below it
                  if (vm.isConnected && vm.selectedPreview != null)
                    Builder(
                      builder: (context) {
                        final preview = selectedPreview!;
                        final s = preview.solicitud;
                        return Positioned(
                          top: 10,
                          left: 5,
                          right: 5,
                          height: previewCardHeight,
                          child: PreviewSolicitudCard(
                            preview: preview,
                            clientPhotoUrl:
                                preview.solicitud.clienteFoto != null &&
                                    preview.solicitud.clienteFoto!.isNotEmpty
                                ? preview.solicitud.clienteFoto
                                : vm.fotoClientePorId(s.clienteId),
                            isLoading: _navigatingToRuta,
                            onClose: () async {
                              if (_navigatingToRuta) return;
                              await _closePreview(vm);
                            },
                            onCancel: () async {
                              if (_navigatingToRuta) return;
                              await _closePreview(vm);
                            },
                            onAccept: () async {
                              try {
                                await vm.aceptarSolicitud(s.id);
                                await _navegarARutaConductor(vm, s.id);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error al aceptar servicio: $e',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            // floatingActionButton removed — button is placed below the map in the Column
            bottomNavigationBar: !vm.isMapExpanded && vm.selectedPreview == null
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
          ));
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

      // Guardar la ubicación del conductor en Firestore para la colección conductores_conectados
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('conductores_conectados').doc(uid).set({
            'ubicacion': {'lat': currentLocation.latitude, 'lng': currentLocation.longitude},
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {
        // ignore write errors
      }

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
                leading: const Icon(Icons.settings),
                title: const Text('Configuracion'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioConductorNavigation.irAConfiguracion(context);
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
}
