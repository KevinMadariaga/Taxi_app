import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/SeleccionDestino.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/DetailsSolicitud.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'dart:async';
import 'package:taxi_app/widgets/perfil.dart';
import 'package:taxi_app/services/ubicacion_servicio.dart';
import '../viewmodels/inicio_cliente_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/MapaClienteModel.dart';

class InicioClienteView extends StatefulWidget {
  const InicioClienteView({super.key});

  @override
  State<InicioClienteView> createState() => _InicioClienteViewState();
}

class _InicioClienteViewState extends State<InicioClienteView> {
  // --- Variables ---
  late InicioClienteViewModel vm;
  final UbicacionService _ubicacionService = UbicacionService();
  late VoidCallback _vmListener;
  LatLng? _currentLocation;
  GoogleMapController? _mapController;
  int _selectedIndex = 0;
  bool _isLoadingLocation = true;
  final PageController _carouselController = PageController(viewportFraction: 0.98);
  int _carouselPage = 0;

  // Configuración visual
  final double _cardScale = 1.0;
  final double _cardPadding = 12.0;
  final double _titleFontScale = 1.0;
  final Color yellow = AppColores.primary;
  final Color _carouselNavButtonColor = AppColores.cardBackground.withOpacity(0.85);

  // --- Ciclo de vida ---
  @override
  void initState() {
    super.initState();
    vm = InicioClienteViewModel();
    _vmListener = () => setState(() {});
    vm.addListener(_vmListener);
    vm.init();
    _isLoadingLocation = true;
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    vm.removeListener(_vmListener);
    vm.dispose();
    super.dispose();
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
    final double baseCarouselHeight = screenH * (isSmallScreen ? 0.22 : (isTablet ? 0.32 : 0.26));
    final double carouselHeight = isTablet ? baseCarouselHeight.clamp(220.0, 340.0) : baseCarouselHeight.clamp(140.0, 220.0);
    // Se elimina el mapa y sus espacios
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppColores.background,
        appBar: AppBar(
          backgroundColor: AppColores.background,
          automaticallyImplyLeading: false,
        ),
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
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSaludoYNombre(scale),
                      SizedBox(height: isTablet ? 32 : 14 * scale),
                      _buildSubtitle(scale),
                      SizedBox(height: isTablet ? 36 : 18 * scale),
                      _buildSearchBox(scale),
                      SizedBox(height: isTablet ? 8 : 1 * scale),
                      _buildFavoritos(scale),
                      SizedBox(height: carouselHeight, child: _buildCarousel()),
                      SizedBox(height: isTablet ? 8 : 2 * scale),
                      // Se elimina el label y el mapa
                      // _buildLocationLabel(scale),
                      // SizedBox(height: labelToMapSpacing),
                      // _buildMap(mapHeight),
                      // SizedBox(height: bottomMapSpacing),
                    ],
                  ),
                ),
              ),
              if (_isLoadingLocation) _buildLoader(),
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
          border: Border.all(color: AppColores.grey200, width: 1),
          boxShadow: const [
            BoxShadow(
              color: AppColores.borderSubtle,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
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
                  color: AppColores.primary, // Cambiado el color aquí
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
    return FutureBuilder<List<UbicacionResultado>>(
      future: _fetchFavoritos(),
      builder: (context, snapshot) {
        final favs = snapshot.data ?? [];
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
      },
    );
  }

  Widget _buildFavoritoItem(UbicacionResultado f, double scale) {
    return Padding(
      padding: EdgeInsets.only(right: 8.0 * scale),
      child: GestureDetector(
        onTap: () => _onFavoriteSelected(f),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
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
        onTap: _navigateToDestinoSeleccion,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
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

  Widget _buildMap(double mapHeight) {
    return SizedBox(
      height: mapHeight,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColores.cardBackground,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppColores.borderSubtle, width: 1.0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: AppGoogleMap(
            initialTarget: _currentLocation ?? const LatLng(8.2595534, -73.353469),
            initialZoom: 14.5,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            onMapCreated: (controller) async {
              _mapController = controller;
              if (_currentLocation != null) {
                await controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentLocation!, 16),
                );
              }
            },
          ),
        ),
      ),
    );
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
                style: TextStyle(
                  color: AppColores.textWhite,
                  fontSize: 16,
                ),
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
            icon: Icon(Icons.directions_car),
            label: 'Viajes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Tú',
          ),
        ],
      ),
    );
  }

  // --- Métodos de lógica ---
  Future<void> _loadCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    final loc = await _ubicacionService.obtenerUbicacionActual();
    if (!mounted) return;
    if (loc != null) {
      setState(() {
        _currentLocation = loc;
        _isLoadingLocation = false;
      });
      if (_mapController != null) {
        await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
      }
      // Guardar ubicación en Firestore al cargar la clase
      try {
        await vm.updateLocation(loc);
      } catch (e) {
        debugPrint('Error al guardar ubicación del cliente: $e');
      }
    } else {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<String> _obtenerDireccionDesdeCoordenadas(LatLng coord) async {
    try {
      final placemarks = await placemarkFromCoordinates(coord.latitude, coord.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final name = p.name?.trim() ?? '';
        final street = p.street?.trim() ?? '';
        final subLocality = p.subLocality?.trim() ?? '';
        final locality = p.locality?.trim() ?? '';
        final parts = <String>[name, street, subLocality, locality].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          return parts.take(2).join(', ');
        }
      }
    } catch (_) {}
    return '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
  }

  Future<List<UbicacionResultado>> _fetchFavoritos() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('ubicaciones')
        .where('userId', isEqualTo: user.uid)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      final nombre = (data['nombre'] ?? '') as String;
      final direccion = (data['direccion'] ?? '') as String;
      final geo = data['ubicacion'] as GeoPoint;
      return UbicacionResultado(
        location: LatLng(geo.latitude, geo.longitude),
        nombre: nombre.isNotEmpty ? nombre : 'Favorito',
        direccion: direccion.isNotEmpty ? direccion : nombre,
      );
    }).toList();
  }

  Future<void> _onFavoriteSelected(UbicacionResultado fav) async {
    if (fav.location == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación no disponible')));
      return;
    }
    final origenPos = _currentLocation ?? fav.location!;
    String origenDireccion = await _obtenerDireccionDesdeCoordenadas(origenPos);
    final origenModel = LocationModel(position: origenPos, title: origenDireccion, subtitle: origenDireccion);
    final destinoModel = LocationModel(position: fav.location!, title: fav.nombre.isNotEmpty ? fav.nombre : fav.direccion, subtitle: fav.direccion);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MapPreview(origen: origenModel, destino: destinoModel)),
    );
  }

  void _navigateToPerfil() {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const PaginaPerfilUsuario(tipoUsuario: 'cliente'),
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() => _selectedIndex = 0);
        });
  }

  void _navigateToDestinoSeleccion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DestinoSeleccionView(currentLocation: _currentLocation),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    if (index == 1) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const HistorialCliente()))
          .then((_) {
            if (!mounted) return;
            setState(() => _selectedIndex = 0);
          });
    } else if (index == 2) {
      _navigateToPerfil();
    } else {
      setState(() => _selectedIndex = index);
    }
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
    final double fontSize = (26 * scale).clamp(20.0, 30.0);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.0 * scale),
      child: Row(
        children: [
          Text(
            'Hola',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppColores.textPrimary,
            ),
          ),
          SizedBox(width: 10 * scale),
          Text(
            firstName.toUpperCase(),
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
      {'title': 'Promociones', 'subtitle': 'Ahorra en tu próximo viaje', 'icon': Icons.local_offer},
      {'title': 'Seguridad', 'subtitle': 'Consejos para un viaje seguro', 'icon': Icons.shield},
      {'title': 'Servicios', 'subtitle': 'Tipos de viaje disponibles', 'icon': Icons.directions_car},
      {'title': 'Soporte', 'subtitle': 'Contacto y ayuda', 'icon': Icons.headset_mic},
    ];
    final double horizontalPaddingOuter = 16.0 * 2;
    final double availableWidth = MediaQuery.of(context).size.width - horizontalPaddingOuter;
    final double viewportFraction = 0.92;
    final double pageWidth = availableWidth * viewportFraction;
    final double screenH = MediaQuery.of(context).size.height;
    final double baseCardHeight = math.min(180.0, screenH * 0.50);
    final double cardHeight = (baseCardHeight * _cardScale).clamp(100.0, screenH * 0.6);
    final double indicatorsHeight = 20.0;
    final double verticalSpacing = 8.0;
    final double totalHeight = cardHeight + indicatorsHeight + verticalSpacing;
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
                  onPageChanged: (idx) => setState(() => _carouselPage = idx),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final double titleFont = (cardHeight * 0.12 * _titleFontScale).clamp(12.0, 36.0).toDouble();
                    final double subtitleFont = (cardHeight * 0.08 * _titleFontScale).clamp(10.0, 20.0).toDouble();
                    return Center(
                      child: SizedBox(
                        width: pageWidth,
                        height: cardHeight,
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                                    colors: [AppColores.overlayLight, Colors.transparent],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: _cardPadding, vertical: _cardPadding),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        (item['title'] ?? 'Promo').toString(),
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
                          final prev = (_carouselPage - 1) < 0 ? (items.length - 1) : (_carouselPage - 1);
                          _carouselController.animateToPage(prev, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          setState(() => _carouselPage = prev);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _carouselNavButtonColor,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: AppColores.borderSubtle, blurRadius: 6)],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(Icons.chevron_left, size: 28, color: AppColores.textPrimary),
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
                          _carouselController.animateToPage(next, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          setState(() => _carouselPage = next);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _carouselNavButtonColor,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: AppColores.borderSubtle, blurRadius: 6)],
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(Icons.chevron_right, size: 28, color: AppColores.textPrimary),
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
                  color: active ? AppColores.textPrimary : AppColores.overlayLight,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
