import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'package:taxi_app/core/modelos/location_model.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

import '../../dominio/entidades/ubicacion_entity.dart';
import '../viewmodels/seleccion_destino_viewmodel.dart';
import 'seleccionar_ubicacion_mapa_view.dart';
import 'widgets/buscador_direccion_widgets.dart';
import 'widgets/favoritos_bottom_sheet.dart';
import 'widgets/pegar_ubicacion_modal.dart';

/// Cambiar el punto de recogida o el destino desde "Detalle de la
/// solicitud": se busca la dirección por texto, se pega una ubicación
/// copiada de un chat o se elige en el mapa. Lo escrito o elegido siempre se
/// confirma en el mapa ([SeleccionarUbicacionMapaView]) y la pantalla se
/// cierra devolviendo el [SeleccionUbicacionResult] confirmado.
class EditarUbicacionScreen extends StatefulWidget {
  const EditarUbicacionScreen({
    super.key,
    required this.actual,
    required this.titulo,
    required this.etiquetaCampo,
    required this.tituloMapa,
    this.cercaDe,
  });

  /// Lo que se está cambiando: "Elegir en el mapa" arranca ahí.
  final LocationModel actual;
  final String titulo;
  final String etiquetaCampo;
  final String tituloMapa;

  /// Punto de referencia para ordenar las sugerencias (el origen).
  final LatLng? cercaDe;

  @override
  State<EditarUbicacionScreen> createState() => _EditarUbicacionScreenState();
}

class _EditarUbicacionScreenState extends State<EditarUbicacionScreen> {
  late final SeleccionDestinoViewModel _vm = SeleccionDestinoViewModel();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _vm.init(posicionInicial: widget.cercaDe ?? widget.actual.position);
    _vm.cargarHistorial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _vm.buscarSugerencias(value),
    );
  }

  Future<void> _cerrarTeclado() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Una selección a la vez: evita dos mapas apilados por doble tap y
  /// muestra la espera mientras se resuelve el lugar.
  Future<void> _conGuarda(Future<void> Function() accion) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await accion();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'EditarUbicacionScreen');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _devolver(SeleccionUbicacionResult resultado) {
    if (!mounted) return;
    Navigator.of(context).pop(resultado);
  }

  /// Confirmar en el mapa lo escrito/elegido y devolverlo.
  Future<void> _confirmarEnMapa(LatLng posicion, String direccion) async {
    await _cerrarTeclado();
    if (!mounted) return;
    final resultado = await Navigator.of(context)
        .push<SeleccionUbicacionResult>(
          MaterialPageRoute(
            builder: (_) => SeleccionarUbicacionMapaView(
              ubicacionInicial: posicion,
              direccionInicial: direccion,
              titulo: widget.tituloMapa,
            ),
          ),
        );
    if (resultado == null) return;
    final texto = resultado.direccion?.trim().isNotEmpty == true
        ? resultado.direccion!.trim()
        : direccion;
    unawaited(
      _vm.registrarDestinoReciente(
        nombre: texto,
        direccion: texto,
        posicion: resultado.position,
      ),
    );
    _devolver(
      SeleccionUbicacionResult(position: resultado.position, direccion: texto),
    );
  }

  Future<void> _tapSugerencia(UbicacionEntity sugerencia) =>
      _conGuarda(() async {
        var posicion = sugerencia.position;
        var direccion = sugerencia.direccion;
        if (posicion == null && sugerencia.placeId != null) {
          final detalle = await _vm.resolverDetalleLugar(sugerencia.placeId!);
          if (detalle?.position == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se pudo abrir esta ubicación.')),
            );
            return;
          }
          posicion = detalle!.position;
          if (detalle.direccion.isNotEmpty) direccion = detalle.direccion;
        }
        if (posicion == null) return;
        await _confirmarEnMapa(posicion, direccion);
      });

  Future<void> _tapHistorial(UbicacionEntity item) => _conGuarda(() async {
    if (item.position == null) return;
    await _confirmarEnMapa(item.position!, item.direccion);
  });

  Future<void> _tapFavoritos() => _conGuarda(() async {
    final favorito = await mostrarFavoritosBottomSheet(context, vm: _vm);
    if (favorito?.position == null || !mounted) return;
    await _confirmarEnMapa(favorito!.position!, favorito.direccion);
  });

  /// El modal de pegar ya confirma en el mapa: se devuelve directo.
  Future<void> _tapPegar() => _conGuarda(() async {
    final resultado = await mostrarPegarUbicacionModal(context, vm: _vm);
    if (resultado != null) _devolver(resultado);
  });

  Future<void> _tapElegirEnMapa() => _conGuarda(
    () => _confirmarEnMapa(
      widget.actual.position,
      widget.actual.title ?? widget.actual.subtitle ?? '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final hPad = MediaQuery.sizeOf(context).width >= 600 ? 32.w : 16.w;
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<SeleccionDestinoViewModel>(
        builder: (context, vm, _) => Scaffold(
          backgroundColor: context.palette.background,
          appBar: appBarNeutra(context, titulo: widget.titulo),
          body: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 12.h),
                      CampoBuscarDireccion(
                        etiqueta: widget.etiquetaCampo,
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: (v) {
                          setState(() {}); // muestra/oculta la X
                          _onChanged(v);
                        },
                        onClear: () {
                          _controller.clear();
                          _vm.limpiarDestino();
                          setState(() {});
                        },
                        onElegirEnMapa: _tapElegirEnMapa,
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        child: vm.sugerencias.isNotEmpty
                            ? ListaSugerencias(
                                sugerencias: vm.sugerencias,
                                onTap: _tapSugerencia,
                              )
                            : SingleChildScrollView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SeccionAcciones(
                                      onFavoritos: _tapFavoritos,
                                      onPegarUbicacion: _tapPegar,
                                    ),
                                    if (vm.historial.isNotEmpty) ...[
                                      SizedBox(height: 8.h),
                                      SeccionHistorial(
                                        historial: vm.historial,
                                        onTap: _tapHistorial,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                if (_ocupado)
                  const OverlayCargando(message: 'Abriendo ubicación...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
