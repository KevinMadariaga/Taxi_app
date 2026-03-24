import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
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

class InicioClienteView extends StatefulWidget {
  const InicioClienteView({super.key, this.authUid});

  final String? authUid;

  @override
  State<InicioClienteView> createState() => _InicioClienteViewState();
}

class _InicioClienteViewState extends State<InicioClienteView>
    with WidgetsBindingObserver {
  // --- Variables ---
  late InicioClienteViewModel vm;
  late VoidCallback _vmListener;
  GoogleMapController? _mapController;
  int _selectedIndex = 1;
  final PageController _carouselController = PageController(
    viewportFraction: 0.98,
  );
  int _carouselPage = 0;
  bool _isPreparingNavigation = false;
  bool _gpsPromptShown = false;
  bool _isRequestingPermissions = false;
  bool _isGpsDialogOpen = false;

  // Configuración visual
  final double _cardScale = 1.0;
  final double _cardPadding = 12.0;
  final double _titleFontScale = 1.0;
  final Color yellow = AppColores.primary;
  final Color _carouselNavButtonColor = AppColores.cardBackground.withOpacity(
    0.85,
  );

  // --- Ciclo de vida ---
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
            const SnackBar(content: Text('Permiso de ubicación no concedido.')),
          );
        }
        if (!granted) return false;
      }

      return true;
    } finally {
      _isRequestingPermissions = false;
    }
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
          onPressed: () {
            _handleAppResumed();
          },
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  // --- Métodos de UI ---
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenH = size.height;
    final double screenW = size.width;
    // Breakpoints para tablets grandes
    final bool isTablet = screenW >= 1000;
    final double scale = isTablet ? 1.25 : (screenW / 375).clamp(0.9, 1.15);
    final bool isSmallScreen = screenH < 700;
    final double baseCarouselHeight =
        screenH * (isSmallScreen ? 0.22 : (isTablet ? 0.32 : 0.26));
    final double carouselHeight = isTablet
        ? baseCarouselHeight.clamp(220.0, 340.0)
        : baseCarouselHeight.clamp(140.0, 220.0);
    // Se elimina el mapa y sus espacios
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppColores.background,
        // AppBar eliminado
        body: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isTablet ? 48.0 : 16.0 * scale,
                  isTablet ? 32.0 : 12.0 * scale,
                  isTablet ? 48.0 : 16.0 * scale,
                  isTablet ? 32.0 : 18.0 * scale,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compactThreshold = isTablet ? 720.0 : 540.0;
                    final useScrollableLayout =
                        constraints.maxHeight < compactThreshold;

                    if (!useScrollableLayout) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSaludoYNombre(scale),
                          SizedBox(height: isTablet ? 20 : 14 * scale),
                          _buildSubtitle(scale),
                          SizedBox(height: isTablet ? 22 : 18 * scale),
                          _buildSearchBox(scale),
                          SizedBox(height: isTablet ? 4 : 1 * scale),
                          _buildFavoritos(scale),
                          SizedBox(
                            height: carouselHeight,
                            child: _buildCarousel(),
                          ),
                          SizedBox(height: isTablet ? 6 : 2 * scale),
                          _buildLocationLabel(scale),
                          SizedBox(height: isTablet ? 8 : 8 * scale),
                          Expanded(child: _buildMap()),
                          SizedBox(height: isTablet ? 8 : 10 * scale),
                        ],
                      );
                    }

                    final compactCarouselHeight = (carouselHeight * 0.82)
                        .clamp(120.0, 180.0)
                        .toDouble();
                    final compactMapHeight = (constraints.maxHeight * 0.34)
                        .clamp(140.0, 220.0)
                        .toDouble();

                    return SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSaludoYNombre(scale),
                            SizedBox(height: 10 * scale),
                            _buildSubtitle(scale),
                            SizedBox(height: 10 * scale),
                            _buildSearchBox(scale),
                            _buildFavoritos(scale),
                            SizedBox(
                              height: compactCarouselHeight,
                              child: _buildCarousel(),
                            ),
                            SizedBox(height: 6 * scale),
                            _buildLocationLabel(scale),
                            SizedBox(height: 6 * scale),
                            SizedBox(
                              height: compactMapHeight,
                              child: _buildMap(),
                            ),
                            SizedBox(height: 8 * scale),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (vm.isLoadingLocation) _buildLoader(),
              if (_isPreparingNavigation) _buildNavigationLoader(),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }

  // --- Métodos de UI auxiliares ---
  Widget _buildSubtitle(double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 15.0 * scale),
      child: Text(
        'Viaje seguro a su destino',
        style: TextStyle(
          color: AppColores.textPrimary,
          fontSize: 18 * scale,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSearchBox(double scale) {
    return GestureDetector(
      onTap: () => _navigateToDestinoSeleccion(),
      child: Container(
        margin: EdgeInsets.only(bottom: 18 * scale),
        decoration: BoxDecoration(
          color: AppColores.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColores.buttonPrimary, width: 2),
          boxShadow: [],
        ),
        padding: EdgeInsets.symmetric(
          vertical: 14 * scale,
          horizontal: 16 * scale,
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColores.buttonPrimary),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(
                '¿A dónde vamos?',
                style: TextStyle(
                  color: AppColores.primary,
                  fontSize: 15 * scale,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColores.buttonPrimary),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritos(double scale) {
    final favs = vm.favoritos;
    final hasFavorites = favs.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: 12.0 * scale, right: 10.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasFavorites
                ? 'Favoritos'
                : 'Sugerencias: agrega tu ubicación favorita',
            style: TextStyle(
              color: AppColores.textSecondary,
              fontSize: 13 * scale,
            ),
          ),
          SizedBox(height: 6 * scale),
          if (vm.isLoadingFavoritos)
            const LinearProgressIndicator(minHeight: 2),
          if (vm.isLoadingFavoritos) SizedBox(height: 6 * scale),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: hasFavorites
                  ? favs.map((f) => _buildFavoritoItem(f, scale)).toList()
                  : ['Casa', 'Trabajo', 'Otros']
                        .map((label) => _buildSugerenciaItem(label, scale))
                        .toList(),
            ),
          ),
          SizedBox(height: 10 * scale),
        ],
      ),
    );
  }

  Widget _buildFavoritoItem(UbicacionResultado f, double scale) {
    return Padding(
      padding: EdgeInsets.only(right: 8.0 * scale),
      child: GestureDetector(
        onTap: () => _onFavoriteSelected(f),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: AppColores.grey200,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColores.borderSubtle),
          ),
          child: Text(
            f.nombre.isNotEmpty ? f.nombre : f.direccion,
            style: TextStyle(
              color: AppColores.textPrimary,
              fontSize: 13 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSugerenciaItem(String label, double scale) {
    return Padding(
      padding: EdgeInsets.only(right: 8.0 * scale),
      child: GestureDetector(
        onTap: () async {
          if (label == 'Casa') {
            final casa = vm.favoritos
                .where((f) {
                  return f.nombre.trim().toLowerCase() == 'casa';
                })
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
          // Si no es 'Casa' o no existe, navega a selección normal
          _navigateToDestinoSeleccion();
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 12 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: AppColores.grey200,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColores.borderSubtle),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppColores.textPrimary,
              fontSize: 13 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationLabel(double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 5.0 * scale),
      child: Text(
        'Estás aquí',
        style: TextStyle(
          fontSize: 20 * scale,
          fontWeight: FontWeight.w800,
          color: AppColores.textPrimary,
        ),
      ),
    );
  }

  Widget _buildMap() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColores.borderSubtle, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
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
            // (overlay removed) map will now occupy full area
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.transparent,
                child: FloatingActionButton.small(
                  heroTag: 'center_marker_btn',
                  backgroundColor: AppColores.surface,
                  onPressed: _centerOnMarker,
                  child: Icon(
                    Icons.my_location,
                    color: AppColores.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildLoader() {
    return Positioned.fill(
      child: Container(
        color: AppColores.overlayDark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
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

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColores.surface,
        border: Border(top: BorderSide(color: AppColores.grey300, width: 1.0)),
      ),
      child: BottomNavigationBar(
        backgroundColor: AppColores.surface,
        elevation: 0,
        selectedItemColor: yellow,
        unselectedItemColor: AppColores.textSecondary,
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Mas opciones',
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

  // --- Métodos de lógica ---
  Future<void> _loadCurrentLocation() async {
    await vm.cargarUbicacionActual();
    if (!mounted) return;
    if (vm.currentLocation != null) {
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(vm.currentLocation!, 16),
        );
      }
    }
  }

  Future<void> _onFavoriteSelected(UbicacionResultado fav) async {
    if (fav.location == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ubicación no disponible')));
      return;
    }
    final origenPos = vm.currentLocation ?? fav.location!;
    String origenDireccion = await vm.obtenerDireccionDesdeCoordenadas(
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
    await InicioClienteNavigation.irAMapaPreview(
      context,
      origenModel,
      destinoModel,
    );
  }

  Future<void> _navigateToPerfil() async {
    await InicioClienteNavigation.irAPerfil(context);
    if (!mounted) return;
    setState(() => _selectedIndex = 0);
  }

  Future<void> _navigateToDestinoSeleccion() async {
    if (_isPreparingNavigation) return;

    if (mounted) {
      setState(() => _isPreparingNavigation = true);
    }

    try {
      String? origenDireccionInicial;
      final currentLocation = vm.currentLocation;
      if (currentLocation != null) {
        final resolved = await vm.obtenerDireccionDesdeCoordenadas(
          currentLocation,
        );
        final cleaned = resolved.trim();
        if (cleaned.isNotEmpty) {
          origenDireccionInicial = cleaned;
        }
      }

      if (!mounted) return;

      await InicioClienteNavigation.irADestinoSeleccion(
        context,
        vm.currentLocation,
        origenDireccionInicial: origenDireccionInicial,
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingNavigation = false);
      }
    }
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == 0) {
      setState(() => _selectedIndex = 0);
      await _showMoreOptionsSheet();
      if (!mounted) return;
      setState(() => _selectedIndex = 1);
    } else if (index == 2) {
      setState(() => _selectedIndex = 2);
      await _navigateToPerfil();
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
                leading: Icon(Icons.security),
                title: Text('Seguridad'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irASeguridad(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.settings),
                title: Text('Configuracion'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irAConfiguracion(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('Ayuda'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irAAyuda(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.support_agent),
                title: Text('Soporte'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irASoporte(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.notifications_none),
                title: Text('Notificaciones'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irANotificaciones(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Historial'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await InicioClienteNavigation.irAHistorial(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    try {
      SystemNavigator.pop();
    } catch (_) {}
    return false;
  }

  Widget _buildSaludoYNombre(double scale) {
    final rawName = vm.clientName.trim();
    String firstName = rawName;
    if (rawName.isNotEmpty) {
      final parts = rawName.split(RegExp(r"\s+"));
      if (parts.isNotEmpty) {
        firstName = parts.first;
      }
    }
    // Formatear: primera letra mayúscula, resto minúscula
    String formattedName = firstName.isNotEmpty
        ? firstName[0].toUpperCase() + firstName.substring(1).toLowerCase()
        : '';
    final double fontSize = (26 * scale).clamp(20.0, 30.0);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0 * scale),
      child: Row(
        children: [
          Text(
            'Hola,',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppColores.textPrimary,
            ),
          ),
          SizedBox(width: 2 * scale),
          Text(
            formattedName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppColores.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    final items = [
      {
        'title': 'Promociones',
        'subtitle': 'Ahorra en tu próximo viaje',
        'icon': Icons.local_offer,
      },
      {
        'title': 'Seguridad',
        'subtitle': 'Consejos para un viaje seguro',
        'icon': Icons.shield,
      },
      {
        'title': 'Servicios',
        'subtitle': 'Tipos de viaje disponibles',
        'icon': Icons.directions_car,
      },
      {
        'title': 'Soporte',
        'subtitle': 'Contacto y ayuda',
        'icon': Icons.headset_mic,
      },
    ];
    final double horizontalPaddingOuter = 16.0 * 2;
    final double availableWidth =
        MediaQuery.of(context).size.width - horizontalPaddingOuter;
    final double viewportFraction = 0.92;
    final double pageWidth = availableWidth * viewportFraction;
    final double screenH = MediaQuery.of(context).size.height;
    final double baseCardHeight = math.min(180.0, screenH * 0.50);
    final double desiredCardHeight = (baseCardHeight * _cardScale).clamp(
      100.0,
      screenH * 0.6,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double indicatorsHeight = 20.0;
        final double verticalSpacing = 8.0;
        final bool hasBoundedHeight = constraints.maxHeight.isFinite;

        final double availableTotalHeight = hasBoundedHeight
            ? constraints.maxHeight
            : (desiredCardHeight + indicatorsHeight + verticalSpacing);
        final double minCardHeight = 84.0;
        final double maxCardHeight = math.max(
          minCardHeight,
          availableTotalHeight - indicatorsHeight - verticalSpacing,
        );
        final double cardHeight = desiredCardHeight
            .clamp(minCardHeight, maxCardHeight)
            .toDouble();
        final double totalHeight =
            cardHeight + indicatorsHeight + verticalSpacing;

        return SizedBox(
          height: totalHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: cardHeight,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _carouselController,
                      itemCount: items.length,
                      onPageChanged: (idx) =>
                          setState(() => _carouselPage = idx),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final double titleFont =
                            (cardHeight * 0.12 * _titleFontScale)
                                .clamp(12.0, 36.0)
                                .toDouble();
                        final double subtitleFont =
                            (cardHeight * 0.08 * _titleFontScale)
                                .clamp(10.0, 20.0)
                                .toDouble();
                        return Center(
                          child: SizedBox(
                            width: pageWidth,
                            height: cardHeight,
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(color: AppColores.grey300),
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          AppColores.overlayLight,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _cardPadding,
                                      vertical: _cardPadding,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            (item['title'] ?? 'Promo')
                                                .toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: titleFont,
                                              fontWeight: FontWeight.w700,
                                              color: AppColores.textWhite,
                                              shadows: const [
                                                Shadow(
                                                  color: AppColores.overlayDark,
                                                  offset: Offset(0, 1),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            (item['subtitle'] ?? '').toString(),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: subtitleFont,
                                              color: AppColores.textWhiteMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (items.length > 1)
                      Positioned(
                        left: 6,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              final prev = (_carouselPage - 1) < 0
                                  ? (items.length - 1)
                                  : (_carouselPage - 1);
                              _carouselController.animateToPage(
                                prev,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                              setState(() => _carouselPage = prev);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: _carouselNavButtonColor,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColores.borderSubtle,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(
                                  Icons.chevron_left,
                                  size: 28,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (items.length > 1)
                      Positioned(
                        right: 6,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              final next = (_carouselPage + 1) % items.length;
                              _carouselController.animateToPage(
                                next,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                              setState(() => _carouselPage = next);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: _carouselNavButtonColor,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColores.borderSubtle,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(6.0),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 28,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (i) {
                  final active = i == _carouselPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 14 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColores.textPrimary
                          : AppColores.overlayLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
