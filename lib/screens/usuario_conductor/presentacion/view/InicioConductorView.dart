import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/navigation/inicio_conductor_navigation.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/InicioConductorViewModel.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/services/notification_service.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/widgets/preview_solicitud_card.dart';
import 'package:taxi_app/widgets/solicitud_card.dart';

class InicioConductor extends StatefulWidget {
  const InicioConductor({Key? key}) : super(key: key);

  @override
  State<InicioConductor> createState() => _InicioConductorState();
}

class _InicioConductorState extends State<InicioConductor> {
  GoogleMapController? _mapController;
  bool _hasCentered = false;
  String? _lastFittedPreviewId;
  bool _hasCenteredForPreview = false;
  bool _navigatingToRuta = false;

  // Expande el mapa ocultando la barra; luego centra los marcadores tras 2s
  Future<void> _expandMapAndCenter(
    PreviewSolicitud preview,
    InicioConductorViewmodel vm,
  ) async {
    if (!mounted) return;
    vm.setMapExpanded(true);

    // Wait 2 seconds to allow UI animation / bottom bar hiding
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    try {
      final s = preview.solicitud;
      final client = LatLng(
        s.ubicacionInicial.latitude,
        s.ubicacionInicial.longitude,
      );
      if (vm.currentLocation != null) {
        await _animateToInclude(vm.currentLocation!, client);
        // Try to fetch route for better polyline (non-blocking)
        vm.fetchRouteOSRM(s.id, vm.currentLocation!, client);
      } else {
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(client, 16),
        );
      }
    } catch (_) {}
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

  Future<void> _animateToInclude(LatLng a, LatLng b) async {
    if (_mapController == null) return;
    try {
      final south = LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      );
      final north = LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      );
      final bounds = LatLngBounds(southwest: south, northeast: north);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100),
      );
    } catch (_) {
      try {
        await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(b, 16));
      } catch (_) {}
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

  double get _previewHeight => MediaQuery.of(context).size.height * 0.35;

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
        // Request necessary permissions for drivers (notifications, foreground and background location)
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await PermissionsHelper.requestAllPermissions(isDriver: true);
          } catch (_) {}
          // Initialize local notifications
          try {
            await NotificationService.instance.init();
          } catch (_) {}
          await vm.init();
        });
        return vm;
      },
      child: Consumer<InicioConductorViewmodel>(
        builder: (context, vm, _) {
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

          // Suscribirse una sola vez a cambios del nombre guardado en cache
          final bool _hasPreview = vm.selectedPreview != null;
          return Scaffold(
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
                                          final double promedio = vm.rating;
                                          final promedioInt = promedio.toInt();
                                          final tieneMedia =
                                              (promedio - promedioInt) >= 0.5;

                                          return Row(
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: List.generate(5, (
                                                  index,
                                                ) {
                                                  if (index < promedioInt) {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.star,
                                                        color:
                                                            AppColores.primary,
                                                        size: 18,
                                                      ),
                                                    );
                                                  } else if (index ==
                                                          promedioInt &&
                                                      tieneMedia) {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.star_half,
                                                        color:
                                                            AppColores.primary,
                                                        size: 18,
                                                      ),
                                                    );
                                                  } else {
                                                    return const Padding(
                                                      padding: EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                      child: Icon(
                                                        Icons.star_border,
                                                        color:
                                                            AppColores.grey400,
                                                        size: 18,
                                                      ),
                                                    );
                                                  }
                                                }),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                promedio > 0
                                                    ? promedio.toStringAsFixed(
                                                        1,
                                                      )
                                                    : '0.0',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color:
                                                      AppColores.textSecondary,
                                                  fontWeight: FontWeight.w700,
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

                      // Reserva espacio para la preview cuando está seleccionada
                      // pero solo si NO hemos expandido el mapa (tap reciente).
                      if (vm.selectedPreview != null && !vm.isMapExpanded)
                        SizedBox(height: _previewHeight + 0),

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
                                          if (vm.currentLocation != null &&
                                              preview != null) {
                                            final driver = vm.currentLocation!;
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
                                            final bearing = vm.calculateBearing(
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
                                      if (sols.isEmpty)
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
                                            if (vm.selectedPreview == null)
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
                  if (vm.selectedPreview != null)
                    Builder(
                      builder: (context) {
                        final preview = vm.selectedPreview!;
                        final s = preview.solicitud;
                        return Positioned(
                          top: 10,
                          left: 5,
                          right: 5,
                          height: _previewHeight,
                          child: GestureDetector(
                            onTap: () => _expandMapAndCenter(preview, vm),
                            child: PreviewSolicitudCard(
                              preview: preview,
                              clientPhotoUrl: vm.fotoClientePorId(s.clienteId),
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
                    currentIndex: 0,
                    selectedItemColor: AppColores.primary,
                    unselectedItemColor: AppColores.textSecondary,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.map),
                        label: 'Mapa',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.history),
                        label: 'Historial',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline),
                        label: 'Tú',
                      ),
                    ],
                    onTap: (index) async {
                      if (index == 0) {
                        // Ya nos encontramos en el inicio, no es necesario hacer pushReplacement
                        return;
                      }
                      if (index == 1) {
                        // Navegar al historial del conductor
                        await InicioConductorNavigation.irAHistorialConductor(
                          context,
                        );
                        return;
                      }
                      if (index == 2) {
                        await _navigateToPerfilConductor();
                      }
                    },
                  )
                : null,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapController = null;
    super.dispose();
  }

  Future<void> _navigateToPerfilConductor() {
    return InicioConductorNavigation.irAPerfilConductor(context);
  }
}
