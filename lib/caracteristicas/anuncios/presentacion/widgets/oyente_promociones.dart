import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/promocion.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import 'ventana_promocion.dart';

/// Invisible, en el inicio de cliente y conductor. Abre la ventana de una
/// promoción en dos casos:
///
/// - **Al tocar su notificación** (local o del sistema) o la fila en la
///   campana: `FcmService.promocionPorAbrir` trae el id.
/// - **Sola**: escucha las promociones recientes y muestra la más nueva que
///   sea para [publico], esté vigente y no se haya visto en este teléfono.
///   Con el inicio a la vista sale apenas el admin la envía.
///
/// Cada promoción se ve una sola vez (por tap o sola). Si hay un viaje u
/// otra pantalla encima, espera a que el inicio vuelva a estar a la vista.
class OyentePromociones extends StatefulWidget {
  const OyentePromociones({
    super.key,
    required this.publico,
    AnunciosRepository? repositorio,
    ValueNotifier<String?>? fuente,
  }) : _repositorio = repositorio,
       _fuente = fuente;

  final AudienciaPromocion publico;
  final AnunciosRepository? _repositorio;
  final ValueNotifier<String?>? _fuente;

  @override
  State<OyentePromociones> createState() => _OyentePromocionesState();
}

class _OyentePromocionesState extends State<OyentePromociones> {
  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  late final ValueNotifier<String?> _fuente =
      widget._fuente ?? FcmService.instance.promocionPorAbrir;
  late final AppLifecycleListener _ciclo;
  StreamSubscription<List<Promocion>>? _sub;
  List<Promocion> _recientes = const [];
  bool _mostrando = false;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _fuente.addListener(_intentar);
    _ciclo = AppLifecycleListener(onResume: _intentar);
    _sub = _repo.watchPromociones(limite: 5).listen(
      (lista) {
        _recientes = lista;
        _intentar();
      },
      onError: (Object e, StackTrace st) =>
          ErrorReporter.report(e, st, reason: 'OyentePromociones'),
    );
    // Tocada con la app cerrada: el id llegó antes que este inicio.
    WidgetsBinding.instance.addPostFrameCallback((_) => _intentar());
  }

  @override
  void dispose() {
    _fuente.removeListener(_intentar);
    _espera?.cancel();
    _ciclo.dispose();
    _sub?.cancel();
    super.dispose();
  }

  /// Espera un instante (deja terminar lo que se esté cerrando, como la
  /// lista de la campana) y revisa si hay algo que mostrar.
  void _intentar() {
    if (_mostrando || !mounted) return;
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), _mostrarSiToca);
  }

  Future<void> _mostrarSiToca() async {
    if (_mostrando || !mounted) return;
    _mostrando = true;
    try {
      if (ModalRoute.of(context)?.isCurrent != true) return;

      final promo = await _siguiente();
      if (promo == null || !mounted) return;
      await _repo.marcarPromocionVista(promo.id);
      if (!mounted) return;
      await mostrarVentanaPromocion(context, promo);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'OyentePromociones');
    } finally {
      _mostrando = false;
      // Un tap que llegó mientras había otra ventana abierta.
      if (mounted && _fuente.value != null) _intentar();
    }
  }

  /// Primero la que pidió el usuario tocando; si no, la que toca mostrar
  /// sola.
  Future<Promocion?> _siguiente() async {
    final pedida = _fuente.value;
    if (pedida != null) {
      _fuente.value = null;
      final promo = await _repo.obtenerPromocion(pedida);
      if (promo == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta promoción ya no está disponible.'),
          ),
        );
      }
      return promo;
    }
    return promocionParaMostrar(
      _recientes,
      publico: widget.publico,
      vistas: await _repo.promocionesVistas(),
      ahora: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
