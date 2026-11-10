import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/vistas/viaje_cliente_screen.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';

import '../datos/viaje_pendiente_repository_impl.dart';
import '../dominio/programacion_viaje.dart';
import '../dominio/viaje_pendiente.dart';
import '../dominio/viaje_pendiente_repository.dart';

/// En el inicio del cliente: su viaje programado o la búsqueda que sigue
/// andando con "Avísame", con la opción de cancelarlos. Si aparece conductor
/// con el inicio a la vista, lo lleva directo al viaje.
class BannerViajePendiente extends StatefulWidget {
  const BannerViajePendiente({
    super.key,
    this.repositorio,
    this.clienteId,
    this.abrirViaje,
  });

  final ViajePendienteRepository? repositorio;
  final String? clienteId;

  /// Por defecto abre `ViajeClienteScreen`.
  final ValueChanged<String>? abrirViaje;

  @override
  State<BannerViajePendiente> createState() => _BannerViajePendienteState();
}

class _BannerViajePendienteState extends State<BannerViajePendiente> {
  ViajePendienteRepository? _repo;
  StreamSubscription<List<ViajePendiente>>? _sub;
  List<ViajePendiente> _viajes = const [];
  final Set<String> _abiertos = {};

  @override
  void initState() {
    super.initState();
    try {
      final uid = widget.clienteId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _repo = widget.repositorio ?? ViajePendienteRepositoryImpl();
      _sub = _repo!
          .watch(uid)
          .listen(
            _alCambiar,
            onError: (Object e, StackTrace st) =>
                ErrorReporter.report(e, st, reason: 'banner_viaje_pendiente'),
          );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'banner_viaje_pendiente');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// `ModalRoute.of` deja esta dependencia: corre de nuevo cuando el inicio
  /// vuelve a estar a la vista. Sin esto, un conductor que acepta con algo
  /// encima (la campana, una promo) no abriría nunca el viaje.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent != true) return;
    // El Navigator no admite un push durante el build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirEncontrados());
  }

  void _alCambiar(List<ViajePendiente> viajes) {
    if (!mounted) return;
    setState(() => _viajes = viajes);
    _abrirEncontrados();
  }

  void _abrirEncontrados() {
    if (!mounted) return;
    for (final v in _viajes) {
      if (v.tipo == TipoViajePendiente.conductorEncontrado) _abrirViaje(v);
    }
  }

  /// Una sola vez por viaje, y solo con el inicio a la vista: si el cliente
  /// abrió la búsqueda, esa pantalla ya navega por su cuenta.
  void _abrirViaje(ViajePendiente v) {
    if (_abiertos.contains(v.id)) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _abiertos.add(v.id);
    final abrir = widget.abrirViaje;
    if (abrir != null) {
      abrir(v.id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViajeClienteScreen(
          viajeId: v.id,
          currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
        ),
      ),
    );
  }

  Future<void> _cancelar(ViajePendiente v) async {
    final programado = v.tipo == TipoViajePendiente.programado;
    final ok = await mostrarConfirmacion(
      context,
      titulo: programado ? 'Cancelar viaje programado' : 'Cancelar búsqueda',
      mensaje: programado
          ? 'Ya no buscaremos conductor para este viaje.'
          : 'Dejaremos de buscar conductor para este viaje.',
      accion: 'Cancelar viaje',
      peligro: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo?.cancelar(v.id);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'banner_viaje_pendiente: cancelar');
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cancelar. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _viajes
        .where((v) => v.tipo != TipoViajePendiente.conductorEncontrado)
        .toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in visibles)
            _Fila(
              viaje: v,
              onCancelar: () => _cancelar(v),
              onVer: v.tipo == TipoViajePendiente.buscandoConAviso
                  ? () => Navigator.of(context).pushNamed(
                      RutasApp.buscandoTaxi,
                      arguments: {'solicitudId': v.id},
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.viaje, required this.onCancelar, this.onVer});

  final ViajePendiente viaje;
  final VoidCallback onCancelar;
  final VoidCallback? onVer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final programado = viaje.tipo == TipoViajePendiente.programado;
    final cuando = viaje.programadaPara;
    final titulo = programado && cuando != null
        ? 'Viaje programado: ${textoFechaProgramada(cuando, DateTime.now())}'
        : 'Seguimos buscando tu conductor';
    final detalle = programado
        ? viaje.destino
        : 'Te avisaremos apenas lo encontremos.';
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColores.primary.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onVer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                programado
                    ? Icons.event_available_rounded
                    : Icons.notifications_active_rounded,
                color: AppColores.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (detalle.isNotEmpty)
                      Text(
                        detalle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancelar viaje',
                onPressed: onCancelar,
                icon: const Icon(Icons.close_rounded, color: AppColores.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
