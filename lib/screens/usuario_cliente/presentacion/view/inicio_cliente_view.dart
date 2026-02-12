import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/seleccion_destino_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/solicitud_preview_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/widgets/google_maps_widget.dart';
import 'dart:async';

import 'package:taxi_app/widgets/perfil.dart';
import 'package:taxi_app/services/ubicacion_servicio.dart';
import '../viewmodels/inicio_cliente_viewmodel.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/mapa_cliente_model.dart';


class InicioClienteView extends StatefulWidget {
  const InicioClienteView({super.key});

  @override
  State<InicioClienteView> createState() => _InicioClienteViewState();
}

class _InicioClienteViewState extends State<InicioClienteView> {
  late InicioClienteViewModel vm;
  final UbicacionService _ubicacionService = UbicacionService();
  late VoidCallback _vmListener;
  LatLng? _currentLocation;
  GoogleMapController? _mapController;
  int _selectedIndex = 0;
  // Estado de carga para obtener la ubicación
  bool _isLoadingLocation = true;
  // Carousel controller and current page index (ajustada para tarjetas más anchas)
  final PageController _carouselController = PageController(viewportFraction: 0.98);
  int _carouselPage = 0;
  // Espacio configurable entre el borde inferior de la pantalla y el mapa

  // Ajustes configurables (valores por defecto)
  final double _cardScale = 1.0;
  final double _cardPadding = 12.0;
  final double _titleFontScale = 1.0;

  final Color yellow = AppColores.primary;

  @override
  void initState() {
    super.initState();
    vm = InicioClienteViewModel();
    _vmListener = () => setState(() {});
    vm.addListener(_vmListener);
    vm.init();
    // Obtener ubicación actual y centrar mapa cuando esté disponible
    _isLoadingLocation = true;
    _loadCurrentLocation();
    // ViewModel `init` handles auth/session/name syncing
  }

  @override
  void dispose() {
    _carouselController.dispose();
    vm.removeListener(_vmListener);
    vm.dispose();
    super.dispose();
  }

  Future<String> _obtenerDireccionDesdeCoordenadas(LatLng coord) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(coord.latitude, coord.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final name = p.name?.trim() ?? '';
        final street = p.street?.trim() ?? '';
        final subLocality = p.subLocality?.trim() ?? '';
        final locality = p.locality?.trim() ?? '';

        final parts = <String>[name, street, subLocality, locality]
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) {
          return parts.take(2).join(', ');
        }
      }
    } catch (_) {}

    return '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });
    final loc = await _ubicacionService.obtenerUbicacionActual();
    if (!mounted) return;
    if (loc != null) {
      setState(() {
        _currentLocation = loc;
        _isLoadingLocation = false;
      });
      // Si el mapa ya está creado, centrar la cámara
      if (_mapController != null) {
        await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
      }
      // Delegar guardado de ubicación al ViewModel
      try {
        await vm.updateLocation(loc);
      } catch (_) {}
    } else {
      // No se obtuvo ubicación: esconder loader igualmente
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dimensiones responsivas para que se vea bien en pantallas pequeñas y grandes
    final double screenH = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenH < 700;

    // Altura del carrusel: compacta en pantallas pequeñas, un poco más amplia en grandes
    final double baseCarouselHeight = screenH * (isSmallScreen ? 0.22 : 0.26);
    final double carouselHeight = baseCarouselHeight.clamp(140.0, 220.0);

    // Altura del mapa: volver al tamaño anterior (más discreto)
    final double mapHeight = math.min(140.0, screenH * 0.16);

    // Espacio inferior entre mapa y bottomNavigationBar
    final double bottomMapSpacing = isSmallScreen
      ? math.max(6.0, screenH * 0.012)
      : math.max(12.0, screenH * 0.02);

    // Espacio entre la etiqueta "Estás aquí" y el mapa
    final double labelToMapSpacing = isSmallScreen
      ? math.max(4.0, screenH * 0.01)
      : math.max(8.0, screenH * 0.015);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18.0, 18.0, 18.0, 18.0),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Client name (fetched from FirebaseAuth)
                    _buildClientName(),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 15.0),
                      child: Text(
                        'Viaje seguro a su destino',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Search box styled as a button — navigates to selection screen
                    GestureDetector(
                      onTap: () async {
                        //Navigate to destination selection screen, pasando la ubicación actual
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => DestinoSeleccionView(currentLocation: _currentLocation)),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.grey.shade200, width: 1),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withAlpha((0.08 * 255).round()), blurRadius: 12, offset: const Offset(0, 6)),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        child: Row(
                          children: const [
                            Icon(Icons.search, color: Colors.black54),
                            SizedBox(width: 12),
                            Expanded(child: Text('¿A dónde vas?', style: TextStyle(color: Colors.black54))),
                            Icon(Icons.chevron_right, color: Colors.black38),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 5),
                    FutureBuilder<List<UbicacionResultado>>(
                      future: _fetchFavoritos(),
                      builder: (context, snapshot) {
                        final favs = snapshot.data ?? [];
                        final hasFavorites = favs.isNotEmpty;

                        return Padding(
                          padding: const EdgeInsets.only(left: 12.0, right: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasFavorites
                                    ? 'Favoritos'
                                    : 'Sugerencias: agrega tu ubicación favorita',
                                style: const TextStyle(color: Colors.black54, fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                    children: hasFavorites
                                      ? favs.map((f) {
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: GestureDetector(
                                              onTap: () => _onFavoriteSelected(f),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: Colors.black12),
                                                ),
                                                child: Text(
                                                  f.nombre.isNotEmpty ? f.nombre : f.direccion,
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList()
                                      : [
                                          'Casa',
                                          'Trabajo',
                                          'Otros',
                                        ].map((label) {
                                          return Padding(
                                            padding: const EdgeInsets.only(right: 8.0),
                                            child: GestureDetector(
                                              onTap: () {
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => DestinoSeleccionView(currentLocation: _currentLocation),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: Colors.black12),
                                                ),
                                                child: Text(
                                                  label,
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        );
                      },
                    ),

                    // Carrusel de cuadros ubicado debajo del botón (tarjetas publicitarias más grandes)
                    SizedBox(
                      height: carouselHeight,
                      child: _buildCarousel(),
                    ),
                    const SizedBox(height: 24),

                    // Mostrar la etiqueta "Estás aquí" arriba del mapa con espacio responsivo
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5.0),
                      child: Text(
                        'Estás aquí',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87),
                      ),
                    ),
                    SizedBox(height: labelToMapSpacing),
                    // Map dentro del scroll, con borde visible en iOS y Android
                    SizedBox(
                      height: mapHeight,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 0, 0, 0),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: const Color.fromARGB(255, 0, 0, 0), width: 1.0),
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
                                await controller.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 16));
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    // Espacio configurable entre el mapa/label y el borde inferior (antes del bottomNavigationBar)
                    SizedBox(height: bottomMapSpacing),
                  ],
                ),
              ),
            ),

            // Overlay loader mientras se obtiene la ubicación (cubre toda la pantalla)
            if (_isLoadingLocation)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withAlpha((0.45 * 255).round()),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Obteniendo ubicación...', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1.0)),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: yellow,
          unselectedItemColor: Colors.black54,
          currentIndex: _selectedIndex,
          onTap: (index) {
            if (index == 1) {
              // Navegar a Historial de Viajes
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HistorialCliente()))
                  .then((_) {
                if (!mounted) return;
                setState(() => _selectedIndex = 0);
              });
            } else if (index == 2) {
              // Navegar a Perfil con una transición más fluida
              _navigateToPerfil();
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.directions_car), label: 'Viajes'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Historial'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Tú'),
          ],
        ),
      ),
    );
  }


  Widget _buildClientName() {
    final name = vm.clientName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Text(
        name.toUpperCase(),
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Colors.black87),
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible')),
      );
      return;
    }

    final origenPos = _currentLocation ?? fav.location!;
    String origenDireccion = await _obtenerDireccionDesdeCoordenadas(origenPos);

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPreview(
          origen: origenModel,
          destino: destinoModel,
        ),
      ),
    );
  }

  void _navigateToPerfil() {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const PaginaPerfilUsuario(tipoUsuario: 'cliente'),
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);

              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.05),
                    end: Offset.zero,
                  ).animate(curved),
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
  // Construye un carrusel simple con indicadores
  Widget _buildCarousel() {
    final items = [
      {'title': 'Promociones', 'subtitle': 'Ahorra en tu próximo viaje', 'icon': Icons.local_offer},
      {'title': 'Seguridad', 'subtitle': 'Consejos para un viaje seguro', 'icon': Icons.shield},
      {'title': 'Servicios', 'subtitle': 'Tipos de viaje disponibles', 'icon': Icons.directions_car},
      {'title': 'Soporte', 'subtitle': 'Contacto y ayuda', 'icon': Icons.headset_mic},
    ];

    // Calcular dimensiones (simplificado): usar una altura base más larga y aplicar escala
    final double horizontalPaddingOuter = 16.0 * 2; // padding exterior en el Scaffold
    final double availableWidth = MediaQuery.of(context).size.width - horizontalPaddingOuter;
    final double viewportFraction = 0.92; // viewport fraction for page width
    final double pageWidth = availableWidth * viewportFraction;
    final double screenH = MediaQuery.of(context).size.height;
    // Altura base mayor para que las cards se vean más largas hacia abajo
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
                              // Placeholder background for future images (keeps aspect visually pleasant)
                              Container(color: Colors.grey.shade300),
                              // Subtle gradient overlay for text readability
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black26, Colors.transparent],
                                  ),
                                ),
                              ),
                              // Centered promo text with configurable padding (title + subtitle)
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
                                          color: Colors.white,
                                          shadows: const [Shadow(color: Colors.black45, offset: Offset(0, 1), blurRadius: 4)],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        (item['subtitle'] ?? '').toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: subtitleFont,
                                          color: Colors.white70,
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
                          decoration: BoxDecoration(color: Colors.white.withAlpha((0.85 * 255).round()), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withAlpha((0.12 * 255).round()), blurRadius: 6)]),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(Icons.chevron_left, size: 28, color: Colors.black87),
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
                          decoration: BoxDecoration(color: Colors.white.withAlpha((0.85 * 255).round()), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withAlpha((0.12 * 255).round()), blurRadius: 6)]),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(Icons.chevron_right, size: 28, color: Colors.black87),
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
                  color: active ? Colors.black87 : Colors.black26,
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
