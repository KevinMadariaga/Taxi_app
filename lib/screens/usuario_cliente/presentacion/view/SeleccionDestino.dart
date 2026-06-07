import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/app_colores.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/MapaClienteModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/DetailsSolicitud.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/MapaPreviewView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/SeleccionaUbicacionEnMapaView.dart';
import 'home_cliente_view.dart';

class DestinoSeleccionView extends StatefulWidget {
  final LatLng? currentLocation;
  final String? origenDireccionInicial;

  const DestinoSeleccionView({
    super.key,
    this.currentLocation,
    this.origenDireccionInicial,
  });

  @override
  State<DestinoSeleccionView> createState() => _DestinoSeleccionViewState();
}

class _DestinoSeleccionViewState extends State<DestinoSeleccionView> {
  bool _isPreparingNavigation = false;
  String _navigationMessage = 'Preparando vista...';
  final Map<String, String> _direccionPrecargadaCache = <String, String>{};

  LatLng? _origenSeleccionado;

  LatLng get _origenActual =>
      _origenSeleccionado ?? widget.currentLocation ?? const LatLng(0, 0);

  String _keyFromLatLng(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  }

  String _coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  String _buildDireccionAmigable(Placemark p, LatLng fallback) {
    final direccion = [
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
    ].where((s) => (s ?? '').trim().isNotEmpty).join(', ');
    if (direccion.trim().isEmpty) return _coordsText(fallback);
    return direccion;
  }

  Future<String> _resolverDireccionOrigenActual() async {
    final origen = _origenActual;
    try {
      final placemarks = await placemarkFromCoordinates(
        origen.latitude,
        origen.longitude,
      );
      if (placemarks.isNotEmpty) {
        return _buildDireccionAmigable(placemarks.first, origen);
      }
    } catch (_) {}
    return _coordsText(origen);
  }

  Future<String> _resolverDireccionParaPunto(LatLng point) async {
    final key = _keyFromLatLng(point);
    final cached = _direccionPrecargadaCache[key];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isNotEmpty) {
        final resolved = _buildDireccionAmigable(placemarks.first, point);
        _direccionPrecargadaCache[key] = resolved;
        return resolved;
      }
    } catch (_) {}

    final fallback = _coordsText(point);
    _direccionPrecargadaCache[key] = fallback;
    return fallback;
  }

  PageRouteBuilder<T> _buildSmoothRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<T?> _runPreparedNavigation<T>({
    required String message,
    required Future<T?> Function() action,
  }) async {
    if (_isPreparingNavigation) return null;
    if (mounted) {
      setState(() {
        _isPreparingNavigation = true;
        _navigationMessage = message;
      });
    }

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingNavigation = false;
          _navigationMessage = 'Preparando vista...';
        });
      }
    }
  }

  Future<void> _abrirMapPreviewConDestino({
    required LatLng destino,
    required String tituloDestino,
    String? direccionDestino,
  }) async {
    await _runPreparedNavigation<void>(
      message: 'Preparando ruta...',
      action: () async {
        final direccionOrigen = await _resolverDireccionOrigenActual();
        if (!mounted) return null;

        await Navigator.of(context).push(
          _buildSmoothRoute(
            MapPreview(
              origen: LocationModel(
                position: _origenActual,
                title: direccionOrigen,
                subtitle: direccionOrigen,
              ),
              destino: LocationModel(
                position: destino,
                title: (direccionDestino?.trim().isNotEmpty == true)
                    ? direccionDestino!.trim()
                    : tituloDestino,
                subtitle: (direccionDestino?.trim().isNotEmpty == true)
                    ? direccionDestino!.trim()
                    : tituloDestino,
              ),
            ),
          ),
        );

        return null;
      },
    );
  }

  Future<String> _solicitarNombreFavorito() async {
    String nombreFavorito = '';
    await showDialog(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: const Text('Nombre del favorito'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ej. Colegio, Gimnasio',
            ),
            onChanged: (value) => nombreFavorito = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    final trimmed = nombreFavorito.trim();
    if (trimmed.isEmpty) return 'Favorito';
    return trimmed;
  }

  Future<SeleccionUbicacionResult?> _abrirSeleccionUbicacionEnMapa({
    required String titulo,
    LatLng? ubicacionInicial,
  }) async {
    return _runPreparedNavigation<SeleccionUbicacionResult>(
      message: 'Preparando mapa...',
      action: () async {
        await _cerrarTecladoAntesDeNavegar();
        if (!mounted) return null;

        final puntoInicial = ubicacionInicial ?? _origenActual;
        final direccionInicial = await _resolverDireccionParaPunto(
          puntoInicial,
        );
        if (!mounted) return null;

        final resultado = await Navigator.of(context).push(
          _buildSmoothRoute(
            SeleccionaUbicacionEnMapaView(
              ubicacionInicial: puntoInicial,
              titulo: titulo,
              direccionInicial: direccionInicial,
            ),
          ),
        );

        if (resultado is SeleccionUbicacionResult) return resultado;
        return null;
      },
    );
  }

  Future<void> _abrirFlujoMapaYPreviewDesdeLista({
    required LatLng ubicacionInicialMapa,
    required String tituloDestino,
    String? direccionDestino,
  }) async {
    final destinoAjustado = await _abrirSeleccionUbicacionEnMapa(
      titulo: 'Ajusta tu destino en el mapa',
      ubicacionInicial: ubicacionInicialMapa,
    );
    if (destinoAjustado == null) return;

    await _abrirMapPreviewConDestino(
      destino: destinoAjustado.position,
      tituloDestino: tituloDestino,
      direccionDestino: destinoAjustado.direccion?.trim().isNotEmpty == true
          ? destinoAjustado.direccion
          : direccionDestino,
    );
  }

  Future<void> _agregarNuevoFavoritoDesdeMapa() async {
    final resultado = await _abrirSeleccionUbicacionEnMapa(
      titulo: 'Selecciona ubicación Favorito',
    );

    if (resultado == null) return;

    final nombre = await _solicitarNombreFavorito();
    await _guardarUbicacionPersonalizada(
      'Favorito',
      resultado.position,
      nombre,
    );
    await _abrirMapPreviewConDestino(
      destino: resultado.position,
      tituloDestino: nombre,
      direccionDestino: resultado.direccion,
    );
  }

  Future<void> _seleccionarYGuardarUbicacion(String tipo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (tipo == 'Favorito') {
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .collection('favoritos')
          .where('tipo', isEqualTo: 'Favorito')
          .get();
      final favoritos = snapshot.docs;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.only(
              top: 24,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Favoritos guardados',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                ...favoritos.map((doc) {
                  final data = doc.data();
                  final geopoint = data['ubicacion'] as GeoPoint?;
                  final nombre = (data['nombre'] ?? 'Favorito') as String;
                  if (geopoint == null) return const SizedBox();
                  return ListTile(
                    leading: const Icon(Icons.star, color: Colors.amber),
                    title: Text(nombre),
                    subtitle: Text(data['direccion'] ?? ''),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await _abrirFlujoMapaYPreviewDesdeLista(
                        ubicacionInicialMapa: LatLng(
                          geopoint.latitude,
                          geopoint.longitude,
                        ),
                        tituloDestino: nombre,
                        direccionDestino: data['direccion']?.toString(),
                      );
                    },
                  );
                }).toList(),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.black54),
                  title: const Text('Agregar nuevo favorito'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _agregarNuevoFavoritoDesdeMapa();
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }
    if (tipo == 'Casa' || tipo == 'Trabajo') {
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .collection('favoritos')
          .where('tipo', isEqualTo: tipo)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final geopoint = data['ubicacion'] as GeoPoint?;
        final nombre = (data['nombre'] ?? tipo) as String;
        if (geopoint != null) {
          await _abrirFlujoMapaYPreviewDesdeLista(
            ubicacionInicialMapa: LatLng(geopoint.latitude, geopoint.longitude),
            tituloDestino: nombre,
            direccionDestino: data['direccion']?.toString(),
          );
          return;
        }
      }
    }
    final resultado = await _abrirSeleccionUbicacionEnMapa(
      titulo: 'Selecciona ubicación de $tipo',
    );
    if (resultado == null) return;

    await _guardarUbicacionPersonalizada(tipo, resultado.position, tipo);
    await _abrirMapPreviewConDestino(
      destino: resultado.position,
      tituloDestino: tipo,
      direccionDestino: resultado.direccion,
    );
  }

  Future<void> _guardarUbicacionPersonalizada(
    String tipo,
    LatLng loc, [
    String? nombrePersonalizado,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar: usuario no autenticado'),
        ),
      );
      return;
    }
    String direccion = '';
    try {
      final placemarks = await placemarkFromCoordinates(
        loc.latitude,
        loc.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => (s ?? '').isNotEmpty).join(', ');
      }
    } catch (_) {}
    if (direccion.isEmpty) {
      direccion =
          '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
    }
    final payload = {
      'userId': user.uid,
      'nombre': nombrePersonalizado ?? tipo,
      'direccion': direccion,
      'ubicacion': GeoPoint(loc.latitude, loc.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'tipo': tipo,
    };

    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('favoritos')
        .add(payload);

    await FirebaseFirestore.instance.collection('ubicaciones').add(payload);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ubicación guardada como "${nombrePersonalizado ?? tipo}"',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColores.textPrimary,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  void _mostrarSnackBarAccionPendiente(String result) {
    if (!mounted) return;
    final message = result == 'agregar'
        ? 'Funcionalidad para agregar ubicación próximamente'
        : result == 'editar'
        ? 'Funcionalidad para editar ubicación próximamente'
        : 'Funcionalidad de comentarios próximamente';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  Future<String?> _mostrarModalRegistrarUbicacion(String tipo) {
    final double topPadding =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final double screenH = MediaQuery.of(context).size.height;
    final double screenW = MediaQuery.of(context).size.width;
    final double horizontalPadding = (screenW * 0.05).clamp(12.0, 32.0);

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Container(
            height: screenH - topPadding,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black54,
                      size: 28,
                    ),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        'Agrega ubicación de ${tipo.toLowerCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.location_on,
                            color: AppColores.buttonPrimary,
                            size: 24,
                          ),
                        ),
                        title: const Text(
                          'Señalar la ubicación en el mapa',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 17,
                          ),
                        ),
                        onTap: () => Navigator.of(ctx).pop('mapa'),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding * 0.2,
                        ),
                        horizontalTitleGap: 16,
                      ),
                      ListTile(
                        leading: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.add,
                            color: Colors.grey,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Agregar ubicación',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 17,
                            color: Colors.grey,
                          ),
                        ),
                        enabled: false,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding * 0.2,
                        ),
                        horizontalTitleGap: 16,
                      ),
                      ListTile(
                        leading: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.grey,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Editar ubicación',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 17,
                            color: Colors.grey,
                          ),
                        ),
                        enabled: false,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding * 0.2,
                        ),
                        horizontalTitleGap: 16,
                      ),
                      ListTile(
                        leading: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.notes,
                            color: Colors.grey,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Otros comentarios',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 17,
                            color: Colors.grey,
                          ),
                        ),
                        enabled: false,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding * 0.2,
                        ),
                        horizontalTitleGap: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _manejarTapUbicacionFrecuente(String tipo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('favoritos')
        .where('tipo', isEqualTo: tipo)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      final geopoint = data['ubicacion'] as GeoPoint?;
      final nombre = (data['nombre'] ?? tipo) as String;
      final direccion = data['direccion'] as String? ?? '';
      if (geopoint != null) {
        await _abrirFlujoMapaYPreviewDesdeLista(
          ubicacionInicialMapa: LatLng(geopoint.latitude, geopoint.longitude),
          tituloDestino: nombre,
          direccionDestino: direccion,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener la ubicación de $tipo.')),
        );
      }
      return;
    }

    final result = await _mostrarModalRegistrarUbicacion(tipo);
    if (result == 'mapa') {
      await _seleccionarYGuardarUbicacion(tipo);
      return;
    }

    if (result != null) {
      _mostrarSnackBarAccionPendiente(result);
    }
  }

  final TextEditingController _origenController = TextEditingController();
  final TextEditingController _destinoController = TextEditingController();
  final FocusNode _origenFocus = FocusNode();
  final FocusNode _destinoFocus = FocusNode();
  // Debounce de búsqueda: evita una consulta a Firestore por cada tecla.
  Timer? _debounce;
  List<UbicacionResultado> _sugerencias = [];
  bool _initialKeyboardOpened = false;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationStatusListener;

  void _requestInitialDestinoFocus() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_destinoFocus);
    _destinoController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _destinoController.text.length,
    );
  }

  void _openKeyboardWhenRouteIsVisible() {
    if (_initialKeyboardOpened || !mounted) return;
    _initialKeyboardOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      _requestInitialDestinoFocus();
    });
  }

  void _clearRouteAnimationListeners() {
    if (_routeAnimation != null) {
      if (_routeAnimationStatusListener != null) {
        _routeAnimation!.removeStatusListener(_routeAnimationStatusListener!);
      }
    }
    _routeAnimation = null;
    _routeAnimationStatusListener = null;
  }

  void _setupKeyboardOpenAfterTransition() {
    if (_initialKeyboardOpened) return;

    final route = ModalRoute.of(context);
    final animation = route?.animation;

    if (route != null && !route.isCurrent) {
      return;
    }

    if (animation == null) {
      _openKeyboardWhenRouteIsVisible();
      return;
    }

    if (animation.status == AnimationStatus.completed) {
      _clearRouteAnimationListeners();
      _openKeyboardWhenRouteIsVisible();
      return;
    }

    if (_routeAnimationStatusListener != null) {
      return;
    }

    _routeAnimation = animation;
    _routeAnimationStatusListener = (status) {
      if (status != AnimationStatus.completed) return;
      _clearRouteAnimationListeners();
      _openKeyboardWhenRouteIsVisible();
    };

    _routeAnimation!.addStatusListener(_routeAnimationStatusListener!);
  }

  @override
  void initState() {
    super.initState();
    _destinoFocus.addListener(() => setState(() {}));
    _origenFocus.addListener(() => setState(() {}));

    final origenInicial = widget.origenDireccionInicial?.trim() ?? '';
    if (origenInicial.isNotEmpty) {
      _origenController.text = origenInicial;
    } else if (widget.currentLocation != null) {
      _setOrigenDesdeCoordenadas(widget.currentLocation!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupKeyboardOpenAfterTransition();
  }

  Future<void> _setOrigenDesdeCoordenadas(LatLng coord) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        coord.latitude,
        coord.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        setState(() {
          _origenController.text = direccion.isNotEmpty
              ? direccion
              : '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (_) {
      setState(() {
        _origenController.text =
            '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clearRouteAnimationListeners();
    _origenController.dispose();
    _destinoController.dispose();
    _destinoFocus.dispose();
    _origenFocus.dispose();
    super.dispose();
  }

  Future<LatLng?> _extraerLatLngDesdeTexto(String text) async {
    final reg = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
    final matches = reg.allMatches(text).toList();
    if (matches.isNotEmpty) {
      final selected = matches.length >= 2 ? matches[1] : matches[0];
      final lat = double.tryParse(selected.group(1) ?? '');
      final lng = double.tryParse(selected.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    final urlMatch = RegExp(r'(https?://[^\s]+)').firstMatch(text);
    final rawUrl = (urlMatch?.group(1) ?? text).trim();
    if (rawUrl.isNotEmpty && rawUrl.contains('google.com/maps')) {
      final atReg = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)(?:,|z)');
      final atMatches = atReg.allMatches(rawUrl).toList();
      if (atMatches.isNotEmpty) {
        if (rawUrl.contains('/place/')) {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        } else if (rawUrl.contains('/dir/')) {
          final m = atMatches.length > 1 ? atMatches[1] : atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        } else {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    try {
      final urlMatch2 = RegExp(r'(https?://[^\s]+)').firstMatch(text);
      final rawUrl2 = (urlMatch2?.group(1) ?? text).trim();
      if (rawUrl2.isEmpty) return null;

      Uri uri;
      try {
        uri = Uri.parse(rawUrl2);
      } catch (_) {
        return null;
      }
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$rawUrl2');
      }

      final client = http.Client();
      try {
        bool isShortGoogleMaps = uri.host.contains('maps.app.goo.gl');
        String target = '';
        if (isShortGoogleMaps) {
          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..maxRedirects = 1
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';

          final resp = await client
              .send(req)
              .timeout(const Duration(seconds: 6));
          target = resp.headers['location'] ?? '';
          if (target.isEmpty) {
            target = await resp.stream.bytesToString();
          }
        } else {
          target = uri.toString();
        }
        if (target.isEmpty) return null;

        final targetMatches = reg.allMatches(target).toList();
        if (targetMatches.isNotEmpty) {
          final selected = targetMatches.length >= 2
              ? targetMatches[1]
              : targetMatches[0];
          final lat = double.tryParse(selected.group(1) ?? '');
          final lng = double.tryParse(selected.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }

        if (isShortGoogleMaps && target.isNotEmpty) {
          try {
            final resp2 = await client
                .get(Uri.parse(target))
                .timeout(const Duration(seconds: 6));
            final html = resp2.body;
            final htmlMatches = reg.allMatches(html).toList();
            if (htmlMatches.isNotEmpty) {
              final selected = htmlMatches.length >= 2
                  ? htmlMatches[1]
                  : htmlMatches[0];
              final lat = double.tryParse(selected.group(1) ?? '');
              final lng = double.tryParse(selected.group(2) ?? '');
              if (lat != null && lng != null) {
                return LatLng(lat, lng);
              }
            }
          } catch (_) {}
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _usarUbicacionDesdeTextoCompartido() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      String text = data?.text?.trim() ?? '';
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
      if (urlMatch != null) {
        text = urlMatch.group(0)!;
      }
      if (text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay texto en el portapapeles')),
        );
        return;
      }

      String linkParaExtraer = text;
      if (text.contains('maps.app.goo.gl')) {
        try {
          final uri = Uri.parse(text);
          final client = http.Client();
          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..maxRedirects = 1
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';
          final resp = await client
              .send(req)
              .timeout(const Duration(seconds: 6));
          final redirected = resp.headers['location'] ?? '';
          if (redirected.isNotEmpty) linkParaExtraer = redirected;
          client.close();
        } catch (_) {}
      }

      final destinoLatLng = await _extraerLatLngDesdeTexto(linkParaExtraer);
      if (destinoLatLng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se encontraron coordenadas en el texto compartido',
            ),
          ),
        );
        return;
      }

      setState(() {
        _destinoController.text = 'Ubicación compartida';
        _sugerencias = [];
      });

      if (!mounted) return;
      FocusScope.of(context).unfocus();

      await _runPreparedNavigation<void>(
        message: 'Abriendo vista previa...',
        action: () async {
          if (!mounted) return null;
          await Navigator.of(context).push(
            _buildSmoothRoute(
              MapaPreviewView(
                location: destinoLatLng,
                direccion: _destinoController.text,
                origenLocation: widget.currentLocation,
                origenDireccion: _origenController.text,
              ),
            ),
          );
          return null;
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al leer la ubicación compartida')),
      );
    }
  }

  Future<void> _guardarUbicacionActualComoFavorita() async {
    final loc = widget.currentLocation;
    if (loc == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar: usuario no autenticado'),
        ),
      );
      return;
    }

    String etiqueta = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Guardar ubicación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elige un nombre para esta ubicación:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Casa'),
                    onPressed: () {
                      etiqueta = 'Casa';
                      Navigator.of(ctx).pop();
                    },
                  ),
                  ActionChip(
                    label: const Text('Trabajo'),
                    onPressed: () {
                      etiqueta = 'Trabajo';
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Otro nombre (opcional):'),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Ej. Colegio de los niños',
                ),
                onChanged: (value) {
                  etiqueta = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                etiqueta = etiqueta.trim();
                Navigator.of(ctx).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (etiqueta.isEmpty) return;

    try {
      String direccion = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          loc.latitude,
          loc.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          direccion = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => (s ?? '').isNotEmpty).join(', ');
        }
      } catch (_) {}

      if (direccion.isEmpty) {
        direccion =
            '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
      }

      final payload = {
        'userId': user.uid,
        'nombre': etiqueta,
        'direccion': direccion,
        'ubicacion': GeoPoint(loc.latitude, loc.longitude),
        'createdAt': FieldValue.serverTimestamp(),
        'tipo': 'Favorito',
      };

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .collection('favoritos')
          .add(payload);

      await FirebaseFirestore.instance.collection('ubicaciones').add(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ubicación guardada como "$etiqueta"')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la ubicación')),
      );
    }
  }

  void _irAInicioCliente() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
    );
  }

  Future<void> _cerrarTecladoAntesDeNavegar() async {
    if (!mounted) return;
    final focused = FocusManager.instance.primaryFocus;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    focused?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (keyboardVisible) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _cerrarTecladoAntesDeVolver() async {
    await _cerrarTecladoAntesDeNavegar();
  }

  Future<bool> _manejarBackConGestoOSistema() async {
    await _cerrarTecladoAntesDeVolver();
    if (!mounted) return false;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return false;
    }

    _irAInicioCliente();
    return false;
  }

  Future<void> _manejarBackConFlecha() async {
    await _cerrarTecladoAntesDeVolver();
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final popped = await navigator.maybePop();
    if (popped) return;

    _irAInicioCliente();
  }

  void _onDestinoChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _sugerencias = []);
      return;
    }
    // Espera 350ms tras la última tecla antes de consultar: teclado fluido.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _buscarUbicacionesHelper(query);
      if (!mounted) return;
      setState(() => _sugerencias = results);
    });
  }

  Future<void> _abrirPreviewDesdeSugerencia(
    UbicacionResultado sugerencia,
  ) async {
    final destinoInicial = sugerencia.location;
    if (destinoInicial == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir esta ubicación.')),
      );
      return;
    }

    await _abrirFlujoMapaYPreviewDesdeLista(
      ubicacionInicialMapa: destinoInicial,
      tituloDestino: sugerencia.nombre.isNotEmpty
          ? sugerencia.nombre
          : 'Destino seleccionado',
      direccionDestino: sugerencia.direccion,
    );
  }

  Future<void> _mostrarFavoritosGuardadosBottomSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('favoritos')
        .where('tipo', isEqualTo: 'Favorito')
        .get();
    final favoritos = snapshot.docs;

    final double topPadding =
        MediaQuery.of(context).padding.top + kToolbarHeight;
    final double screenH = MediaQuery.of(context).size.height;
    final double screenW = MediaQuery.of(context).size.width;
    final double horizontalPadding = (screenW * 0.05).clamp(12.0, 32.0);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Container(
            height: screenH - topPadding,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black54,
                      size: 28,
                    ),
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 16.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      const Text(
                        'Favoritos guardados',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (favoritos.isEmpty) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.add,
                              color: Colors.black54,
                              size: 22,
                            ),
                          ),
                          title: const Text(
                            'Agregar nuevo favorito',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 17,
                            ),
                          ),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await _agregarNuevoFavoritoDesdeMapa();
                          },
                        ),
                        const SizedBox(height: 8),
                      ] else ...[
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(context).viewInsets.bottom + 8,
                            ),
                            children: [
                              ...favoritos.map((doc) {
                                final data = doc.data();
                                final geopoint =
                                    data['ubicacion'] as GeoPoint?;
                                final nombre =
                                    (data['nombre'] ?? 'Favorito') as String;
                                if (geopoint == null) return const SizedBox();
                                return ListTile(
                                  leading: const Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                  ),
                                  title: Text(nombre),
                                  subtitle: Text(data['direccion'] ?? ''),
                                  onTap: () async {
                                    Navigator.of(ctx).pop();
                                    await _abrirFlujoMapaYPreviewDesdeLista(
                                      ubicacionInicialMapa: LatLng(
                                        geopoint.latitude,
                                        geopoint.longitude,
                                      ),
                                      tituloDestino: nombre,
                                      direccionDestino:
                                          data['direccion']?.toString(),
                                    );
                                  },
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.add,
                              color: Colors.black54,
                              size: 22,
                            ),
                          ),
                          title: const Text(
                            'Agregar nuevo favorito',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 17,
                            ),
                          ),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await _agregarNuevoFavoritoDesdeMapa();
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tap origen extraído ───────────────────────────────────────────────────

  Future<void> _tapOrigen() async {
    final resultado = await _abrirSeleccionUbicacionEnMapa(
      titulo: 'Selecciona origen',
      ubicacionInicial: widget.currentLocation ?? _origenSeleccionado,
    );
    if (resultado == null) return;
    setState(() {
      _origenSeleccionado = resultado.position;
      _origenController.text =
          (resultado.direccion?.trim().isNotEmpty == true)
          ? resultado.direccion!
          : '${resultado.position.latitude.toStringAsFixed(6)}, ${resultado.position.longitude.toStringAsFixed(6)}';
    });
  }

  // ── UI builders ───────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColores.surface,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: AppColores.textPrimary,
        ),
        onPressed: _manejarBackConFlecha,
      ),
      title: const Text(
        '¿A dónde vamos?',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColores.textPrimary,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColores.borderSubtle),
      ),
    );
  }

  Widget _buildSearchCard(double hPad, double textFieldFontSize) {
    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 12, hPad, 0),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            // Fila origen
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColores.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _origenController,
                    focusNode: _origenFocus,
                    readOnly: true,
                    onTap: _tapOrigen,
                    style: TextStyle(
                      fontSize: textFieldFontSize,
                      color: AppColores.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Selecciona tu origen',
                      hintStyle: TextStyle(
                        fontSize: textFieldFontSize * 0.9,
                        color: AppColores.textSecondary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.star_border_rounded,
                          size: 20,
                          color: AppColores.primary,
                        ),
                        tooltip: 'Guardar ubicación',
                        onPressed: _guardarUbicacionActualComoFavorita,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Conector visual entre origen y destino
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: AppColores.grey300,
                  ),
                  const Expanded(
                    child: Divider(height: 1, color: AppColores.borderSubtle),
                  ),
                ],
              ),
            ),
            // Fila destino
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColores.textSecondary,
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _destinoController,
                    focusNode: _destinoFocus,
                    autofocus: false,
                    style: TextStyle(
                      fontSize: textFieldFontSize,
                      color: AppColores.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Selecciona un destino',
                      hintStyle: TextStyle(
                        fontSize: textFieldFontSize * 0.9,
                        color: AppColores.textSecondary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      suffixIcon: _destinoFocus.hasFocus
                          ? IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppColores.textSecondary,
                              ),
                              onPressed: () {
                                _destinoController.clear();
                                setState(() => _sugerencias = []);
                              },
                            )
                          : null,
                    ),
                    onChanged: _onDestinoChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAccessItem({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  Widget _buildQuickAccessSection() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildQuickAccessItem(
            icon: Icons.home_rounded,
            label: 'Casa',
            onTap: () => _manejarTapUbicacionFrecuente('Casa'),
          ),
          const SizedBox(width: 8),
          _buildQuickAccessItem(
            icon: Icons.work_rounded,
            label: 'Trabajo',
            onTap: () => _manejarTapUbicacionFrecuente('Trabajo'),
          ),
          const SizedBox(width: 8),
          _buildQuickAccessItem(
            icon: Icons.star_rounded,
            label: 'Favoritos',
            onTap: _mostrarFavoritosGuardadosBottomSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildSugerenciaTile(UbicacionResultado sugerencia) {
    final nombre = sugerencia.nombre.isNotEmpty
        ? sugerencia.nombre
        : sugerencia.direccion;
    final direccion = sugerencia.direccion;
    final showDireccion =
        direccion.isNotEmpty && direccion != sugerencia.nombre;

    return InkWell(
      onTap: () => _abrirPreviewDesdeSugerencia(sugerencia),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColores.grey100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: AppColores.textSecondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColores.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showDireccion) ...[
                    const SizedBox(height: 2),
                    Text(
                      direccion,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColores.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColores.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSugerenciasSection() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _sugerencias.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        indent: 64,
        color: AppColores.borderSubtle,
      ),
      itemBuilder: (_, i) => _buildSugerenciaTile(_sugerencias[i]),
    );
  }

  Widget _buildPegarUbicacionRow(double hPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GestureDetector(
        onTap: _usarUbicacionDesdeTextoCompartido,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColores.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColores.borderSubtle),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.content_paste_rounded,
                size: 18,
                color: AppColores.textSecondary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pegar ubicación desde el portapapeles',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColores.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppColores.overlayDark,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColores.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColores.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _navigationMessage,
                    style: const TextStyle(
                      color: AppColores.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 600;
    final double hPad = isTablet ? 32.0 : 16.0;
    final double textFieldFontSize = (screenW / 390 * 16).clamp(14.0, 20.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _manejarBackConGestoOSistema(),
      child: Scaffold(
        backgroundColor: AppColores.background,
        appBar: _buildAppBar(),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchCard(hPad, textFieldFontSize),
                  const SizedBox(height: 16),
                  if (_sugerencias.isEmpty)
                    // Scrollable para que al abrir el teclado el contenido se
                    // desplace en vez de desbordar (sin overflow).
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPad),
                              child: _buildQuickAccessSection(),
                            ),
                            const SizedBox(height: 16),
                            _buildPegarUbicacionRow(hPad),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(child: _buildSugerenciasSection()),
                ],
              ),
              if (_isPreparingNavigation) _buildNavigationOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}


Future<List<UbicacionResultado>> _buscarUbicacionesHelper(String query) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return [];
  }

  final snapshot = await FirebaseFirestore.instance
      .collection('ubicaciones')
      .get();
  final normalizado = query.toLowerCase();
  return snapshot.docs
      .where((doc) {
        final data = doc.data();
        final nombre = (data['nombre'] ?? '') as String;
        final direccion = (data['direccion'] ?? '') as String;
        final ownerId = data['userId'] as String?;

        if (ownerId != null && ownerId.isNotEmpty && ownerId != user.uid) {
          return false;
        }

        final textoBusqueda = '$nombre $direccion'.toLowerCase();
        return textoBusqueda.contains(normalizado);
      })
      .map((doc) {
        final data = doc.data();
        final geopoint = data['ubicacion'] as GeoPoint;
        final nombre = (data['nombre'] ?? '') as String;
        final direccion = (data['direccion'] ?? '') as String;
        return UbicacionResultado(
          location: LatLng(geopoint.latitude, geopoint.longitude),
          nombre: nombre,
          direccion: direccion.isNotEmpty ? direccion : nombre,
        );
      })
      .toList();
}
