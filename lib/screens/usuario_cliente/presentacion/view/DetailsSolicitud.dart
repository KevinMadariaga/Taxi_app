import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscar_destino_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/mapapreview_viewmodel.dart';
import 'package:taxi_app/widgets/MapaGoogle.dart';
import 'SeleccionaUbicacionEnMapaView.dart';

import 'package:taxi_app/core/app_colores.dart';

class MapPreview extends StatefulWidget {
  final LocationModel origen;
  final LocationModel destino;

  const MapPreview({super.key, required this.origen, required this.destino});

  @override
  State<MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<MapPreview> {

  GoogleMapController? _controller;
  late MapapreviewViewModel _vm;
  BitmapDescriptor? _destIcon;
  VoidCallback? _vmListener;
  String? _origenDireccionActual;
  bool _resolviendoOrigenDireccion = false;

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

  Future<void> _handleBackNavigation() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final popped = await navigator.maybePop();
    if (popped || !mounted) return;

    await navigator.pushReplacement(
      _buildSmoothRoute(
        BuscarDestinoView(currentLocation: widget.origen.position),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _vm = MapapreviewViewModel(origen: widget.origen, destino: widget.destino);
    _vm.init();
    _vmListener = () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyPerspective(),
      );
    };
    _vm.addListener(_vmListener!);
    _loadDestIcon();
    _resolverDireccionOrigen();
  }

  String _coordsText(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  Future<void> _resolverDireccionOrigen() async {
    final origenPos = widget.origen.position;
    final subtitle = widget.origen.subtitle?.trim() ?? '';
    if (subtitle.isNotEmpty) {
      if (!mounted) return;
      setState(() => _origenDireccionActual = subtitle);
      return;
    }

    if (mounted) {
      setState(() {
        _resolviendoOrigenDireccion = true;
      });
    }

    try {
      final placemarks = await placemarkFromCoordinates(
        origenPos.latitude,
        origenPos.longitude,
      );

      if (!mounted) return;

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.isNotEmpty).join(', ');

        setState(() {
          _origenDireccionActual = direccion.isNotEmpty
              ? direccion
              : _coordsText(origenPos);
          _resolviendoOrigenDireccion = false;
        });
        return;
      }

      setState(() {
        _origenDireccionActual = _coordsText(origenPos);
        _resolviendoOrigenDireccion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _origenDireccionActual = _coordsText(origenPos);
        _resolviendoOrigenDireccion = false;
      });
    }
  }

  Future<void> _loadDestIcon() async {
    try {
      final dpr = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      final icon = await BitmapDescriptor.asset(
        ImageConfiguration(size: const Size(30, 50), devicePixelRatio: dpr),
        'assets/img/map_pin_red.png',
      );
      if (!mounted) return;
      setState(() => _destIcon = icon);
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPerspective());
  }

  Future<void> _applyPerspective() async {
    if (_controller == null) return;
    final bounds = _vm.cameraBounds;
    if (bounds == null) return;
    try {
      await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (_vmListener != null) _vm.removeListener(_vmListener!);
    _controller?.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MapapreviewViewModel>.value(
      value: _vm,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            backgroundColor: AppColores.surface.withOpacity(0.95),
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'Detalle de la solicitud',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: _handleBackNavigation,
            ),
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
          ),
          body: LayoutBuilder(builder: (context, constraints) {
            final resp = ResponsiveHelper.getResponsiveData(context);
            double bottomPct;
            if (resp.deviceType == DeviceType.mobile) {
              bottomPct = 40.0; // smaller bottom area on mobile -> taller map
            } else if (resp.deviceType == DeviceType.tablet) {
              bottomPct = 30.0; // tablet: reduce bottom to increase map
            } else {
              bottomPct = 25.0; // desktop: even smaller bottom
            }

            final bottomHeight = ResponsiveHelper.hp(context, bottomPct).clamp(140.0, constraints.maxHeight * 0.6) as double;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Expanded(child: _buildMapFlexible(context)),
                SizedBox(height: bottomHeight, child: _buildBottomContent(context)),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMapFlexible(BuildContext context) {
    return Center(
      child: LayoutBuilder(builder: (ctx, constraints) {
        final width = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width * 0.92;
        return Container(
          width: width * 0.92,
          // height left unconstrained so it fills the Expanded area
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Consumer<MapapreviewViewModel>(
            builder: (context, vm, _) {
              final origen = vm.origen.position;
              final destino = vm.destino.position;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Mapagoogle(
                      initialTarget: LatLng(
                        (origen.latitude + destino.latitude) / 2,
                        (origen.longitude + destino.longitude) / 2,
                      ),
                      initialZoom: 13,
                      myLocationEnabled: true,
                      onMapCreated: _onMapCreated,
                      markers: {
                        // Marker(
                        //   markerId: const MarkerId('origen'),
                        //   position: origen,
                        //   infoWindow: InfoWindow(
                        //     title: 'Origen',
                        //     snippet: vm.origen.subtitle,
                        //   ),
                        //   icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        // ),
                        Marker(
                          markerId: const MarkerId('destino'),
                          position: destino,
                          infoWindow: InfoWindow(
                            title: vm.destino.title ?? 'Destino',
                            snippet: vm.destino.subtitle,
                          ),
                          icon: _destIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                      },
                      polylines: vm.polylines,
                    ),
                    if (vm.isLoadingRoute)
                      Positioned.fill(
                        child: Container(
                          color: Colors.white.withOpacity(0.6),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: AppColores.primary),
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
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _buildBottomContent(BuildContext context) {
    return Consumer<MapapreviewViewModel>(
      builder: (context, vm, _) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.wp(context, 4),
                  ResponsiveHelper.hp(context, 1.2),
                  ResponsiveHelper.wp(context, 4),
                  ResponsiveHelper.hp(context, 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLocationCard(context, vm),
                    SizedBox(height: ResponsiveHelper.hp(context, 1)),
                    _buildDestinationCard(context, vm),
                    SizedBox(height: ResponsiveHelper.hp(context, 1)),
                    _buildServiceValue(context, vm),
                    SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                    _buildSubmitButton(context, vm),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocationCard(BuildContext context, MapapreviewViewModel vm) {
    return _buildLocationInfoCard(
      context,
      header: 'Tu ubicación actual',
      value: _resolviendoOrigenDireccion
          ? 'Buscando ubicación actual...'
          : (_origenDireccionActual ?? vm.origen.title ?? 'Ubicación'),
      icon: Icons.location_on_outlined,
      iconBorderColor: Colores.amarillo,
      cardBorderRadius: ResponsiveHelper.wp(context, 4),
    );
  }

  Widget _buildDestinationCard(BuildContext context, MapapreviewViewModel vm) {
    return GestureDetector(
      onTap: () async {
        final inicial = vm.destino.position;
        final direccionInicial = vm.destino.title ?? vm.destino.subtitle;
        final resultado = await Navigator.of(context).push<LatLng>(
          _buildSmoothRoute(
            SeleccionaUbicacionEnMapaView(
              ubicacionInicial: inicial,
              titulo: 'Ajusta tu destino en el mapa',
              direccionInicial: direccionInicial,
            ),
          ),
        );

        if (resultado is LatLng) {
          if (!mounted) return;
          setState(() {});
          String resolved = '${resultado.latitude.toStringAsFixed(6)}, ${resultado.longitude.toStringAsFixed(6)}';
          try {
            final placemarks = await placemarkFromCoordinates(
              resultado.latitude,
              resultado.longitude,
            );
            if (placemarks.isNotEmpty) {
              final p = placemarks.first;
              final direccion = [
                p.street,
                p.subLocality,
                p.locality,
                p.administrativeArea,
              ].where((s) => s != null && s.isNotEmpty).join(', ');
              if (direccion.isNotEmpty) resolved = direccion;
            }
          } catch (_) {}

          // Recreate ViewModel with updated destino
          if (_vmListener != null) _vm.removeListener(_vmListener!);
          _controller?.dispose();
          _vm.dispose();

          final nuevoDestino = LocationModel(position: resultado, title: resolved, subtitle: resolved);
          setState(() {
            _vm = MapapreviewViewModel(origen: widget.origen, destino: nuevoDestino);
            _vm.init();
            _vmListener = () {
              if (!mounted) return;
              WidgetsBinding.instance.addPostFrameCallback((_) => _applyPerspective());
            };
            _vm.addListener(_vmListener!);
          });
        }
      },
      child: _buildLocationInfoCard(
        context,
        header: '¿Adónde va?',
        value: vm.destino.title ?? vm.destino.subtitle ?? 'Destino',
        icon: Icons.place,
        iconBorderColor: Colors.black12,
        cardBorderRadius: ResponsiveHelper.wp(context, 3),
      ),
    );
  }

  Widget _buildLocationInfoCard(
    BuildContext context, {
    required String header,
    required String value,
    required IconData icon,
    required Color iconBorderColor,
    required double cardBorderRadius,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardBorderRadius),
        border: Border.all(color: Colores.amarillo, width: 1.5),
        color: AppColores.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.wp(context, 2)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.wp(context, 5),
              ),
              border: Border.all(color: iconBorderColor),
            ),
            child: Icon(icon, color: Colors.black54),
          ),
          SizedBox(width: ResponsiveHelper.wp(context, 3)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 12),
                    color: AppColores.textSecondary,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: ResponsiveHelper.sp(context, 14),
                    color: AppColores.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirModalMetodoPago(
    BuildContext context,
    MapapreviewViewModel vm,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final bottomGap = media.viewPadding.bottom + 10;

        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, bottomGap),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text(
                      'Metodo de pago',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('Seleccionado: ${vm.metodoPago}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Efectivo'),
                    selected: vm.metodoPago == 'Efectivo',
                    trailing: vm.metodoPago == 'Efectivo'
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      vm.setMetodoPago('Efectivo');
                      Navigator.of(ctx).pop();
                    },
                  ),
                  ListTile(
                    leading: Image.asset(
                      'assets/img/nequi.jpeg',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                    title: const Text('Nequi'),
                    selected: vm.metodoPago == 'Nequi',
                    trailing: vm.metodoPago == 'Nequi'
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      vm.setMetodoPago('Nequi');
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceValue(BuildContext context, MapapreviewViewModel vm) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.hp(context, 2),
        horizontal: ResponsiveHelper.wp(context, 3),
      ),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(ResponsiveHelper.wp(context, 2)),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        'Valor del servicio: ${vm.valorServicio}',
        style: TextStyle(
          fontSize: ResponsiveHelper.sp(context, 16),
          fontWeight: FontWeight.w700,
          color: AppColores.textPrimary,
        ),
      ),
    );
  }

  Future<void> _abrirModalComentarios(
    BuildContext context,
    MapapreviewViewModel vm,
  ) async {
    final controller = TextEditingController(text: vm.comentario);
    String draft = vm.comentario;
    const sugerencias = <String>[
      'Llevo mascota',
      'Llevo maletas',
      'Taxi grande',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final keyboardInset = media.viewInsets.bottom;
        final bottomGap = keyboardInset > 0
            ? keyboardInset + 10
            : media.viewPadding.bottom + 10;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
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
                        'Comentario para el conductor',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        vm.comentario.isEmpty
                            ? 'Sin comentario guardado'
                            : 'Guardado: ${vm.comentario}',
                        style: const TextStyle(color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: sugerencias
                            .map(
                              (s) => ActionChip(
                                label: Text(s),
                                onPressed: () {
                                  setSheetState(() {
                                    draft = s;
                                    controller.text = s;
                                    controller.selection =
                                        TextSelection.collapsed(
                                          offset: controller.text.length,
                                        );
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        maxLines: 3,
                        onChanged: (value) {
                          setSheetState(() {
                            draft = value.trim();
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Escribe un comentario...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            vm.setComentario(draft);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Guardar comentario'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSubmitButton(BuildContext context, MapapreviewViewModel vm) {
    final buttonHeight = ResponsiveHelper.hp(context, 6.5);
    return Row(
      children: [
        SizedBox(
          width: buttonHeight,
          height: buttonHeight,
          child: Tooltip(
            message: 'Metodo: ${vm.metodoPago}',
            child: OutlinedButton(
              onPressed: () => _abrirModalMetodoPago(context, vm),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 2),
                  ),
                ),
                side: const BorderSide(color: Colors.black26),
                foregroundColor: Colors.black87,
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.wp(context, 2)),
        Expanded(
          child: SizedBox(
            height: buttonHeight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colores.amarillo,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 2),
                  ),
                ),
              ),
              onPressed: vm.isSubmitting
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      final solicitudId = await vm.crearSolicitud();
                      if (!mounted) return;
                      if (solicitudId != null) {
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) =>
                                BuscandoTaxiView(solicitudId: solicitudId),
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Error al crear la solicitud'),
                          ),
                        );
                      }
                    },
              child: vm.isSubmitting
                  ? SizedBox(
                      width: ResponsiveHelper.wp(context, 5),
                      height: ResponsiveHelper.wp(context, 5),
                      child: const CircularProgressIndicator(
                        color: Colors.black87,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Buscar conductor',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.sp(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColores.textWhite,
                      ),
                    ),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.wp(context, 2)),
        SizedBox(
          width: buttonHeight,
          height: buttonHeight,
          child: Tooltip(
            message: vm.comentario.isEmpty
                ? 'Sin comentario'
                : 'Comentario guardado',
            child: OutlinedButton(
              onPressed: () => _abrirModalComentarios(context, vm),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    ResponsiveHelper.wp(context, 2),
                  ),
                ),
                side: const BorderSide(color: Colors.black26),
                foregroundColor: Colors.black87,
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                vm.comentario.isEmpty ? Icons.comment_outlined : Icons.comment,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
