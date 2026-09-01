import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/caracteristicas/confirmar_solicitud/presentacion/vistas/confirmar_solicitud_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/widgets/boton.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../viewmodels/seleccion_destino_viewmodel.dart';
import 'seleccionar_ubicacion_mapa_view.dart';
import 'widgets/favoritos_bottom_sheet.dart';
import 'widgets/pegar_ubicacion_modal.dart';

/// Pantalla de selección de destino. Reemplaza a la legacy
/// `DestinoSeleccionView` (`screens/.../SeleccionDestino.dart`) — misma forma
/// de constructor para que los call-sites existentes no cambien.
class SeleccionDestinoScreen extends StatefulWidget {
  const SeleccionDestinoScreen({
    super.key,
    this.currentLocation,
    this.origenDireccionInicial,
  });

  final LatLng? currentLocation;
  final String? origenDireccionInicial;

  @override
  State<SeleccionDestinoScreen> createState() => _SeleccionDestinoScreenState();
}

class _SeleccionDestinoScreenState extends State<SeleccionDestinoScreen> {
  late final SeleccionDestinoViewModel _vm = SeleccionDestinoViewModel();
  final TextEditingController _destinoController = TextEditingController();
  final FocusNode _destinoFocus = FocusNode();
  Timer? _debounce;

  bool _isPreparingNavigation = false;
  String _navigationMessage = 'Preparando...';

  @override
  void initState() {
    super.initState();
    _vm.init(
      posicionInicial: widget.currentLocation,
      direccionInicial: widget.origenDireccionInicial,
    );
    _vm.cargarHistorial();
    _destinoFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destinoController.dispose();
    _destinoFocus.dispose();
    _vm.dispose();
    super.dispose();
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  void _onDestinoChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _vm.buscarSugerencias(value);
    });
  }

  Future<void> _cerrarTeclado() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Guarda única de "una acción de selección a la vez" para TODA la lista
  /// (favoritos, pegar, sugerencia, historial, elegir en el mapa): antes
  /// cada handler tenía su propio criterio (algunos ninguno), así que un
  /// doble tap sobre un ítem de la lista —muy fácil cuando hay que esperar
  /// la resolución de Places antes de navegar— podía disparar el mismo
  /// tap dos veces (dos `Navigator.push` apilados). Bloquea de inmediato
  /// (antes de cualquier `await`) y muestra el overlay de carga desde el
  /// primer toque, no solo en el paso final — es la parte que se sentía
  /// "lenta" porque no había ninguna señal visual entre el tap y que algo
  /// pasara.
  Future<void> _conGuardaDeSeleccion(
    Future<void> Function() accion, {
    String mensaje = 'Abriendo ubicación...',
  }) async {
    if (_isPreparingNavigation) return;
    setState(() {
      _isPreparingNavigation = true;
      _navigationMessage = mensaje;
    });
    try {
      await accion();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SeleccionDestinoScreen');
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingNavigation = false;
          _navigationMessage = 'Preparando...';
        });
      }
    }
  }

  Future<void> _tapFavoritos() => _conGuardaDeSeleccion(() async {
    final favorito = await mostrarFavoritosBottomSheet(context, vm: _vm);
    if (favorito == null || favorito.position == null || !mounted) return;
    await _confirmarUbicacionYNavegar(favorito.position!, favorito.direccion);
  });

  /// El pegado ya pasa por `SeleccionarUbicacionMapaView` dentro del propio
  /// modal (ver `mostrarPegarUbicacionModal`) y devuelve un resultado ya
  /// confirmado — a diferencia de favoritos/sugerencias, acá no hace falta
  /// un segundo paso de mapa, se va directo al preview.
  Future<void> _tapPegarUbicacion() => _conGuardaDeSeleccion(() async {
    final resultado = await mostrarPegarUbicacionModal(context, vm: _vm);
    if (resultado == null || !mounted) return;
    final direccion = resultado.direccion?.trim().isNotEmpty == true
        ? resultado.direccion!.trim()
        : _vm.coordsText(resultado.position);
    _destinoController.text = direccion;
    await _irAMapPreview(resultado.position, direccion);
  });

  Future<void> _tapSugerencia(UbicacionEntity sugerencia) =>
      _conGuardaDeSeleccion(() async {
        var posicion = sugerencia.position;
        var direccion = sugerencia.direccion;

        // Único paso realmente lento del flujo: sin posición cacheada hay
        // que resolver el detalle del lugar contra Places (red + Cloud
        // Function). El overlay ya está visible desde `_conGuardaDeSeleccion`
        // antes de llegar acá, así que la espera se ve, no se siente
        // colgada.
        if (posicion == null && sugerencia.placeId != null) {
          final detalle = await _vm.resolverDetalleLugar(sugerencia.placeId!);
          if (detalle == null || detalle.position == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo abrir esta ubicación.'),
              ),
            );
            return;
          }
          posicion = detalle.position;
          if (detalle.direccion.isNotEmpty) direccion = detalle.direccion;
        }
        if (posicion == null) return;

        await _confirmarUbicacionYNavegar(posicion, direccion);
      });

  Future<void> _tapHistorial(UbicacionEntity item) =>
      _conGuardaDeSeleccion(() async {
        final posicion = item.position;
        if (posicion == null) return;
        await _confirmarUbicacionYNavegar(posicion, item.direccion);
      });

  /// El usuario elige "Elegir en el mapa" en vez de buscar por texto:
  /// arranca en el origen ya conocido (o `currentLocation` si el origen
  /// todavía no resolvió) y reusa el mismo picker con pin central que ya
  /// usan favoritos/sugerencias/pegar — hereda gratis el registro en
  /// historial y la navegación al preview.
  Future<void> _tapElegirEnMapa() => _conGuardaDeSeleccion(() async {
    final origen = _vm.origenPosition ?? widget.currentLocation;
    if (origen == null) return;
    await _confirmarUbicacionYNavegar(
      origen,
      _vm.coordsText(origen),
      titulo: 'Elige tu destino en el mapa',
    );
  });

  /// Toda selección de destino (sugerencia de búsqueda, favorito o "elegir
  /// en el mapa") pasa por acá: abre el mapa movible ya centrado en esa
  /// ubicación para que el usuario la ajuste/confirme, y al confirmar sigue
  /// directo al preview — esta pantalla ya no tiene un botón de "confirmar
  /// destino" propio. Ya corre dentro de la guarda de `_conGuardaDeSeleccion`
  /// (todos sus llamadores pasan por ahí), así que no repite su propio guard.
  Future<void> _confirmarUbicacionYNavegar(
    LatLng posicionInicial,
    String direccionInicial, {
    String titulo = 'Confirma tu destino',
  }) async {
    await _cerrarTeclado();
    if (!mounted) return;
    final resultado = await Navigator.of(context)
        .push<SeleccionUbicacionResult>(
          MaterialPageRoute(
            builder: (_) => SeleccionarUbicacionMapaView(
              ubicacionInicial: posicionInicial,
              direccionInicial: direccionInicial,
              titulo: titulo,
            ),
          ),
        );
    if (resultado == null || !mounted) return;
    final direccionFinal = resultado.direccion?.trim().isNotEmpty == true
        ? resultado.direccion!.trim()
        : direccionInicial;
    _destinoController.text = direccionFinal;
    unawaited(
      _vm.registrarDestinoReciente(
        nombre: direccionFinal,
        direccion: direccionFinal,
        posicion: resultado.position,
      ),
    );
    await _irAMapPreview(resultado.position, direccionFinal);
  }

  /// Sin guard propio: todos sus llamadores (`_tapPegarUbicacion`,
  /// `_confirmarUbicacionYNavegar`) ya corren dentro de
  /// `_conGuardaDeSeleccion`.
  Future<void> _irAMapPreview(LatLng destino, String destinoDireccion) async {
    final origen = _vm.origenPosition;
    if (origen == null) return;

    if (mounted) setState(() => _navigationMessage = 'Preparando ruta...');
    await _cerrarTeclado();
    if (!mounted) return;

    final origenModel = LocationModel(
      position: origen,
      title: _vm.origenDireccion,
      subtitle: _vm.origenDireccion,
    );
    final destinoModel = LocationModel(
      position: destino,
      title: destinoDireccion,
      subtitle: destinoDireccion,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConfirmarSolicitudView(origen: origenModel, destino: destinoModel),
      ),
    );
  }

  Future<bool> _manejarBack() async {
    await _cerrarTeclado();
    if (!mounted) return false;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return false;
    }
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeClienteView()),
    );
    return false;
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width >= 600;
    final double hPad = isTablet ? 32.w : 16.w;

    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SeleccionDestinoViewModel>(
        builder: (context, vm, _) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (_, _) => _manejarBack(),
            child: Scaffold(
              backgroundColor: AppColores.background,
              appBar: AppBar(
                backgroundColor: AppColores.surface,
                elevation: 0,
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: AppColores.textPrimary,
                  ),
                  onPressed: () async {
                    if (await _manejarBack()) return;
                  },
                ),
                title: Text(
                  '¿A dónde vamos?',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColores.textPrimary,
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppColores.borderSubtle),
                ),
              ),
              body: SafeArea(
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 16.h),
                          _DestinoField(
                            controller: _destinoController,
                            focusNode: _destinoFocus,
                            onChanged: _onDestinoChanged,
                            onClear: () {
                              _destinoController.clear();
                              _vm.limpiarDestino();
                            },
                            onElegirEnMapa: _tapElegirEnMapa,
                          ),
                          SizedBox(height: 12.h),
                          Expanded(
                            child: vm.sugerencias.isNotEmpty
                                ? _SugerenciasList(
                                    sugerencias: vm.sugerencias,
                                    onTap: _tapSugerencia,
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (vm.historial.isNotEmpty) ...[
                                          _HistorialSection(
                                            historial: vm.historial,
                                            onTap: _tapHistorial,
                                          ),
                                          SizedBox(height: 8.h),
                                        ],
                                        _AccionesSection(
                                          onFavoritos: _tapFavoritos,
                                          onPegarUbicacion: _tapPegarUbicacion,
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          SizedBox(height: 12.h),
                        ],
                      ),
                    ),
                    if (_isPreparingNavigation)
                      _NavigationOverlay(message: _navigationMessage),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Secciones visuales
// ─────────────────────────────────────────────────────────────────────────────

class _DestinoField extends StatelessWidget {
  const _DestinoField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.onElegirEnMapa,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onElegirEnMapa;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColores.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu Destino..',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColores.textSecondary,
            ),
          ),
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: AppColores.grey100,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColores.textSecondary,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColores.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escribe una dirección (ej. Carrera 10 # 5-20)',
                      hintStyle: TextStyle(
                        fontSize: 13.sp,
                        color: AppColores.textSecondary,
                      ),
                      // El tema global define `filled`/bordes por-estado
                      // (enabled/focused) para todo TextField — solo pisar
                      // `border` no alcanza, esos ganan por sobre el
                      // genérico y el campo dibujaba su propio recuadro
                      // blanco anidado dentro de este contenedor gris.
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                    onChanged: onChanged,
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColores.textSecondary,
                    ),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          CustomButton(
            text: 'Elegir en el mapa',
            width: double.infinity,
            height: 44.h,
            fontSize: 13.sp,
            color: AppColores.grey100,
            textColor: AppColores.textPrimary,
            borderColor: AppColores.borderSubtle,
            icon: const Icon(
              Icons.map_rounded,
              size: 16,
              color: AppColores.primary,
            ),
            onPressed: onElegirEnMapa,
          ),
        ],
      ),
    );
  }
}

class _SugerenciasList extends StatelessWidget {
  const _SugerenciasList({required this.sugerencias, required this.onTap});

  final List<UbicacionEntity> sugerencias;
  final ValueChanged<UbicacionEntity> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sugerencias.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1.h, indent: 64, color: AppColores.borderSubtle),
      itemBuilder: (context, i) {
        final sugerencia = sugerencias[i];
        final nombre = sugerencia.nombre.isNotEmpty
            ? sugerencia.nombre
            : sugerencia.direccion;
        final mostrarDireccion =
            sugerencia.direccion.isNotEmpty &&
            sugerencia.direccion != sugerencia.nombre;
        return InkWell(
          onTap: () => onTap(sugerencia),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
            child: Row(
              children: [
                Container(
                  width: 36.w,
                  height: 36.w,
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
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: AppColores.textPrimary,
                        ),
                      ),
                      if (mostrarDireccion) ...[
                        SizedBox(height: 2.h),
                        Text(
                          sugerencia.direccion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColores.textSecondary,
                          ),
                        ),
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
}

/// Historial de destinos elegidos antes — mismo estilo de fila que
/// [_SugerenciasList], pero con ícono de reloj (son ubicaciones ya vistas,
/// no resultados de una búsqueda nueva).
class _HistorialSection extends StatelessWidget {
  const _HistorialSection({required this.historial, required this.onTap});

  final List<UbicacionEntity> historial;
  final ValueChanged<UbicacionEntity> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in historial)
          InkWell(
            onTap: () => onTap(item),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: const BoxDecoration(
                      color: AppColores.grey100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: AppColores.textSecondary,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      item.direccion.isNotEmpty ? item.direccion : item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Divider(height: 1.h, indent: 64, color: AppColores.borderSubtle),
      ],
    );
  }
}

class _AccionesSection extends StatelessWidget {
  const _AccionesSection({
    required this.onFavoritos,
    required this.onPegarUbicacion,
  });

  final VoidCallback onFavoritos;
  final VoidCallback onPegarUbicacion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CustomButton(
            text: 'Favoritos',
            width: double.infinity,
            height: 48.h,
            fontSize: 13.sp,
            color: AppColores.surface,
            textColor: AppColores.textPrimary,
            borderColor: AppColores.borderSubtle,
            icon: const Icon(
              Icons.star_rounded,
              size: 16,
              color: AppColores.primary,
            ),
            onPressed: onFavoritos,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: CustomButton(
            text: 'Pegar ubicación',
            width: double.infinity,
            height: 48.h,
            fontSize: 13.sp,
            color: AppColores.surface,
            textColor: AppColores.textPrimary,
            borderColor: AppColores.borderSubtle,
            icon: const Icon(
              Icons.content_paste_rounded,
              size: 16,
              color: AppColores.primary,
            ),
            onPressed: onPegarUbicacion,
          ),
        ),
      ],
    );
  }
}

class _NavigationOverlay extends StatelessWidget {
  const _NavigationOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: AppColores.overlayDark,
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 28.w),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            decoration: BoxDecoration(
              color: AppColores.surface,
              borderRadius: BorderRadius.circular(16.r),
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
                SizedBox(width: 12.w),
                Flexible(
                  child: Text(
                    message,
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
}
