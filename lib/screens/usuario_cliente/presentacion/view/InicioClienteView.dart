import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/helper/permisos_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/navigation/inicio_cliente_navigation.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'dart:async';
import '../viewmodels/inicio_cliente_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/MapaClienteModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/widgets/perfil.dart';

class InicioClienteView extends StatefulWidget {
  const InicioClienteView({super.key, this.authUid});

  final String? authUid;

  @override
  State<InicioClienteView> createState() => _InicioClienteViewState();
}

class _InicioClienteViewState extends State<InicioClienteView>
    with WidgetsBindingObserver {
  late InicioClienteViewModel vm;
  late VoidCallback _vmListener;
  GoogleMapController? _mapController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 1;
  final PageController _carouselController = PageController(
    viewportFraction: 0.92,
  );
  bool _isPreparingNavigation = false;
  bool _gpsPromptShown = false;
  bool _isRequestingPermissions = false;
  bool _isGpsDialogOpen = false;

  // ── Ciclo de vida ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vm = InicioClienteViewModel();
    _vmListener = () => setState(() {});
    vm.addListener(_vmListener);
    vm.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapClienteLocationFlow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _carouselController.dispose();
    vm.removeListener(_vmListener);
    vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _handleAppResumed();
  }

  // ── Lógica de ubicación / GPS ────────────────────────────────────────────

  Future<void> _bootstrapClienteLocationFlow() async {
    if (widget.authUid != null && widget.authUid!.isNotEmpty) {
      await vm.hydrateFromUid(widget.authUid!);
    }
    final ready = await _ensureLocationServiceAndPermission();
    if (!ready) return;
    await _loadCurrentLocation();
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
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permiso de ubicación no concedido.'),
            ),
          );
        }
        if (!granted) return false;
      }
      return true;
    } finally {
      _isRequestingPermissions = false;
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
      if (_gpsPromptShown) {
        _showGpsRetrySnackBar();
        return;
      }
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
    _gpsPromptShown = false;
    await _ensureLocationServiceAndPermission();
    await _loadCurrentLocation();
  }

  Future<bool> _showGpsDisabledDialog() async {
    if (!mounted) return false;
    _isGpsDialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
      ),
    );
    _isGpsDialogOpen = false;
    return result == true;
  }

  Future<bool> _showRequestLocationPermissionDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
      ),
    );
    return result == true;
  }

  void _showGpsSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showGpsRetrySnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('GPS sigue desactivado.'),
        action: SnackBarAction(
          label: 'Reintentar',
          onPressed: _handleAppResumed,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  Future<void> _loadCurrentLocation() async {
    await vm.cargarUbicacionActual();
    if (!mounted) return;
    if (vm.currentLocation != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(vm.currentLocation!, 16),
      );
    }
  }

  Future<void> _onFavoriteSelected(UbicacionResultado fav) async {
    if (fav.location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible')),
      );
      return;
    }
    final origenPos = vm.currentLocation ?? fav.location!;
    final origenDireccion = await vm.obtenerDireccionDesdeCoordenadas(
      origenPos,
    );
    final origenModel = LocationModel(
      position: origenPos,
      title: origenDireccion,
      subtitle: origenDireccion,
    );
    final destinoModel = LocationModel(
      position: fav.location!,
      title: fav.nombre.isNotEmpty ? fav.nombre : fav.direccion,
      subtitle: fav.direccion,
    );
    if (!mounted) return;
    try {
      FocusScope.of(context).unfocus();
    } catch (_) {}
    await InicioClienteNavigation.irAMapaPreview(
      context,
      origenModel,
      destinoModel,
    );
  }

  Future<void> _navigateToDestinoSeleccion() async {
    if (_isPreparingNavigation) return;
    try {
      FocusScope.of(context).unfocus();
    } catch (_) {}
    if (mounted) setState(() => _isPreparingNavigation = true);
    try {
      String? origenDireccionInicial;
      final currentLocation = vm.currentLocation;
      if (currentLocation != null) {
        final resolved = await vm.obtenerDireccionDesdeCoordenadas(
          currentLocation,
        );
        final cleaned = resolved.trim();
        if (cleaned.isNotEmpty) origenDireccionInicial = cleaned;
      }
      if (!mounted) return;
      await InicioClienteNavigation.irADestinoSeleccion(
        context,
        vm.currentLocation,
        origenDireccionInicial: origenDireccionInicial,
      );
    } finally {
      if (mounted) setState(() => _isPreparingNavigation = false);
    }
  }

  Future<void> _onBottomNavTap(int index) async {
    try {
      FocusScope.of(context).unfocus();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _centerOnMarker() async {
    if (!mounted) return;
    if (vm.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible')),
      );
      return;
    }
    if (_mapController != null) {
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(vm.currentLocation!, 16),
        );
      } catch (_) {}
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 600;

    final SystemUiOverlayStyle overlayStyle = _selectedIndex == 0
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.amber)
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.white);
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);

    final double hPad = isTablet ? 32.0 : 16.0;
    final double carouselHeight =
        (size.height * (isTablet ? 0.30 : 0.29)).clamp(160.0, 240.0);
    final double mapHeight =
        (size.height * (isTablet ? 0.26 : 0.24)).clamp(145.0, 205.0);

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        key: _scaffoldKey,
        backgroundColor: AppColores.background,
        endDrawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Seguridad'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await InicioClienteNavigation.irASeguridad(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Ayuda'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await InicioClienteNavigation.irAAyuda(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent),
                  title: const Text('Soporte'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await InicioClienteNavigation.irASoporte(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Notificaciones'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await InicioClienteNavigation.irANotificaciones(context);
                  },
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            Container(
              height: MediaQuery.of(context).padding.top,
              color: _selectedIndex == 0 ? Colors.amber : Colors.white,
            ),
            SafeArea(
              child: Stack(
                children: [
                  IndexedStack(
                    index: _selectedIndex,
                    children: [
                      // 0 - Historial
                      const HistorialCliente(),

                      // 1 - Home
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bloque superior: header + search + favoritos
                          Padding(
                            padding: EdgeInsets.fromLTRB(hPad, 45, hPad, 0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(isTablet),
                                const SizedBox(height: 12),
                                _buildSearchBox(isTablet),
                                const SizedBox(height: 16),
                                _buildFavoritos(isTablet),
                              ],
                            ),
                          ),
                          // Bloque inferior: carousel + mapa anclados al fondo
                          Expanded(
                            child: Padding(
                              padding:
                                  EdgeInsets.fromLTRB(hPad, 20, hPad, 10),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: carouselHeight,
                                    child: _buildCarousel(),
                                  ),
                                  const SizedBox(height: 35),
                                  SizedBox(
                                    height: mapHeight,
                                    child: _buildMap(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // 2 - Perfil
                      const PaginaPerfilUsuario(tipoUsuario: 'cliente'),
                    ],
                  ),
                  if (vm.isLoadingLocation) _buildLoader(),
                  if (_isPreparingNavigation) _buildNavigationLoader(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  // ── Secciones visuales ────────────────────────────────────────────────────

  Widget _buildHeader(bool isTablet) {
    final rawName = vm.clientName.trim();
    String firstName = rawName;
    if (rawName.isNotEmpty) {
      final parts = rawName.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) firstName = parts.first;
    }
    final formattedName = firstName.isNotEmpty
        ? firstName[0].toUpperCase() + firstName.substring(1).toLowerCase()
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola${formattedName.isNotEmpty ? ", $formattedName" : ""}',
                style: TextStyle(
                  fontSize: isTablet ? 27 : 25,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '¿A dónde vas hoy?',
                style: TextStyle(
                  fontSize: isTablet ? 16 : 15,
                  fontWeight: FontWeight.w500,
                  color: AppColores.textSecondary,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColores.grey100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.menu_rounded,
              size: 22,
              color: AppColores.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBox(bool isTablet) {
    return GestureDetector(
      onTap: () => _navigateToDestinoSeleccion(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColores.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColores.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColores.primary.withValues(alpha: 0.15),
              child: const Icon(
                Icons.my_location_rounded,
                size: 14,
                color: AppColores.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '¿A dónde quieres ir?',
                style: TextStyle(
                  color: AppColores.textSecondary,
                  fontSize: isTablet ? 18 : 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColores.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColores.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritos(bool isTablet) {
    final favs = vm.favoritos;
    final hasFavorites = favs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasFavorites
              ? 'Ubicaciones favoritas'
              : 'Sugerencias: agrega tu ubicación favorita',
          style: TextStyle(
            color: AppColores.textSecondary,
            fontSize: isTablet ? 13 : 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        if (vm.isLoadingFavoritos) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: hasFavorites
                ? favs.map((f) => _buildFavoritoItem(f)).toList()
                : ['Casa', 'Trabajo', 'Otros']
                      .map((label) => _buildSugerenciaItem(label))
                      .toList(),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFavoritoItem(UbicacionResultado f) {
    final label = f.nombre.isNotEmpty ? f.nombre : f.direccion;
    final icon = label.trim().toLowerCase() == 'casa'
        ? Icons.home_rounded
        : Icons.star_rounded;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _onFavoriteSelected(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColores.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColores.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColores.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColores.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSugerenciaItem(String label) {
    final IconData icon;
    switch (label) {
      case 'Casa':
        icon = Icons.home_rounded;
        break;
      case 'Trabajo':
        icon = Icons.work_rounded;
        break;
      default:
        icon = Icons.explore_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () async {
          if (label == 'Casa') {
            final casa = vm.favoritos
                .where((f) => f.nombre.trim().toLowerCase() == 'casa')
                .cast<UbicacionResultado?>()
                .firstWhere((f) => f != null, orElse: () => null);
            if (casa != null && casa.location != null) {
              await InicioClienteNavigation.irAMapaPreviewFavoritoCasa(
                context,
                casa.location!,
                casa.direccion,
              );
              return;
            }
          }
          _navigateToDestinoSeleccion();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColores.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColores.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColores.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColores.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarousel() {
    final items = [
      {
        'title': '¿Quieres promocionar\ntu negocio?',
        'subtitle': 'Comunícate con nosotros',
        'icon': Icons.campaign_rounded,
      },
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _carouselController,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Fondo degradado
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColores.primary.withValues(alpha: 0.85),
                                AppColores.primary,
                              ],
                            ),
                          ),
                        ),
                        // Círculo decorativo top-right
                        Positioned(
                          right: -20,
                          top: -20,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        // Contenido
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 30,
                                color: AppColores.textPrimary.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                item['title'].toString(),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item['subtitle'].toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColores.textPrimary.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            AppGoogleMap(
              initialTarget:
                  vm.currentLocation ?? const LatLng(8.2595534, -73.353469),
              initialZoom: 14.5,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              markers: vm.conductoresMarkers,
              onMapCreated: (controller) async {
                _mapController = controller;
                if (vm.currentLocation != null) {
                  await controller.animateCamera(
                    CameraUpdate.newLatLngZoom(vm.currentLocation!, 16),
                  );
                }
              },
            ),
            // Label "Estás aquí"
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 12,
                      color: AppColores.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Estás aquí',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Botón centrar mapa
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColores.surface,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 21,
                    onPressed: _centerOnMarker,
                    icon: const Icon(
                      Icons.my_location,
                      color: AppColores.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColores.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        backgroundColor: AppColores.surface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColores.primary,
        unselectedItemColor: AppColores.textSecondary,
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Mapa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Positioned.fill(
      child: Container(
        color: AppColores.overlayDark,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'Obteniendo ubicación...',
                style: TextStyle(color: AppColores.textWhite, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationLoader() {
    return Positioned.fill(
      child: Container(
        color: AppColores.overlayDark,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                'Preparando destino...',
                style: TextStyle(color: AppColores.textWhite, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
