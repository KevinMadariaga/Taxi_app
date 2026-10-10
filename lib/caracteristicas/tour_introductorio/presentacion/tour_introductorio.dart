import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../datos/tour_repository_impl.dart';
import '../dominio/tour_repository.dart';
import 'paso_tour.dart';

/// Muestra el recorrido introductorio solo la primera vez que [uid] entra a
/// la pantalla [tourId]. Se marca como visto ANTES de mostrarlo (mismo
/// criterio que la bienvenida): si la app se cierra a mitad, no vuelve a
/// salir en cada arranque.
Future<void> mostrarTourSiEsPrimeraVez(
  BuildContext context, {
  required String tourId,
  required String uid,
  required List<PasoTour> pasos,
  TourRepository? repositorio,
}) async {
  final repo = repositorio ?? TourRepositoryImpl();
  try {
    if (uid.isEmpty || await repo.yaVisto(tourId, uid)) return;
    // Solo se marca si de verdad se va a mostrar: si en este momento no hay
    // ninguna parte en pantalla (p. ej. el conductor con una solicitud
    // abierta), se intenta de nuevo la próxima vez en vez de perderlo.
    if (!pasos.any((p) => rectGlobalDe(p.objetivo) != null)) return;
    await repo.marcarVisto(tourId, uid);
    if (!context.mounted) return;
    await mostrarTourIntroductorio(context, pasos);
  } catch (e, st) {
    ErrorReporter.report(e, st, reason: 'tour introductorio ($tourId)');
  }
}

/// Muestra el recorrido ahora, sin mirar si ya se vio.
Future<void> mostrarTourIntroductorio(
  BuildContext context,
  List<PasoTour> pasos,
) async {
  final visibles = pasos.where((p) => rectGlobalDe(p.objetivo) != null);
  if (visibles.isEmpty) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Recorrido de la pantalla',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => TourIntroductorio(pasos: visibles.toList()),
  );
}

/// Rectángulo en pantalla del widget de [clave], o `null` si no está montado.
Rect? rectGlobalDe(GlobalKey clave) {
  final box = clave.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Velo oscuro con un foco que viaja de un elemento a otro, un anillo que
/// late alrededor y una tarjeta con la explicación y la navegación.
class TourIntroductorio extends StatefulWidget {
  const TourIntroductorio({super.key, required this.pasos});

  final List<PasoTour> pasos;

  @override
  State<TourIntroductorio> createState() => _TourIntroductorioState();
}

class _TourIntroductorioState extends State<TourIntroductorio>
    with TickerProviderStateMixin {
  /// Mueve el foco entre pasos. El primero arranca desde la pantalla entera
  /// y se cierra sobre el elemento: es el efecto de "zoom".
  late final AnimationController _foco = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final CurvedAnimation _focoCurva = CurvedAnimation(
    parent: _foco,
    curve: Curves.easeInOutCubic,
  );

  /// Latido del anillo alrededor del elemento iluminado.
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  int _indice = 0;
  Rect? _desde;
  Rect? _hasta;
  bool _sinAnimaciones = false;

  PasoTour get _paso => widget.pasos[_indice];
  bool get _esUltimo => _indice == widget.pasos.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sinAnimaciones = MediaQuery.disableAnimationsOf(context);
    if (_sinAnimaciones) {
      _pulso.stop();
    } else if (!_pulso.isAnimating) {
      _pulso.repeat();
    }
    if (_hasta == null) {
      // Primer paso: desde toda la pantalla hacia el elemento.
      _desde = Offset.zero & MediaQuery.sizeOf(context);
      _irA(0);
    }
  }

  void _irA(int indice) {
    final destino = _rectConMargen(widget.pasos[indice]);
    setState(() {
      _desde = _rectActual ?? _desde;
      _indice = indice;
      _hasta = destino ?? _hasta;
    });
    if (_sinAnimaciones) {
      _foco.value = 1;
    } else {
      _foco.forward(from: 0);
    }
  }

  Rect? _rectConMargen(PasoTour paso) =>
      rectGlobalDe(paso.objetivo)?.inflate(paso.margen);

  Rect? get _rectActual {
    final desde = _desde, hasta = _hasta;
    if (hasta == null) return desde;
    if (desde == null) return hasta;
    return Rect.lerp(desde, hasta, _focoCurva.value);
  }

  void _siguiente() {
    if (_esUltimo) {
      Navigator.of(context).pop();
    } else {
      _irA(_indice + 1);
    }
  }

  void _atras() {
    if (_indice > 0) _irA(_indice - 1);
  }

  @override
  void dispose() {
    _focoCurva.dispose();
    _foco.dispose();
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tamano = MediaQuery.sizeOf(context);
    final relleno = MediaQuery.paddingOf(context);
    final hasta = _hasta ?? Offset.zero & tamano;

    return PopScope(
      // Atrás del sistema cierra el recorrido.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // El velo no deja tocar la pantalla de abajo.
                child: AnimatedBuilder(
                  animation: Listenable.merge([_foco, _pulso]),
                  builder: (context, _) => CustomPaint(
                    painter: _VeloConFoco(
                      foco: _rectActual ?? hasta,
                      radio: _paso.radio,
                      pulso: _sinAnimaciones ? 0 : _pulso.value,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: relleno.top + 8,
              right: 12,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text(
                  'Saltar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            _TarjetaPosicionada(
              foco: hasta,
              tamano: tamano,
              relleno: relleno,
              child: AnimatedSwitcher(
                duration: _sinAnimaciones
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                // La tarjeta que sale no recibe toques: un doble toque
                // rápido en "Siguiente" avanzaba dos pasos.
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (_, c) => IgnorePointer(
                    ignoring: animation.status == AnimationStatus.reverse,
                    child: c,
                  ),
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                ),
                child: _TarjetaPaso(
                  key: ValueKey(_indice),
                  paso: _paso,
                  indice: _indice,
                  total: widget.pasos.length,
                  onAtras: _indice > 0 ? _atras : null,
                  onSiguiente: _siguiente,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ubica la tarjeta debajo del foco si hay espacio, si no encima; si el
/// elemento ocupa casi toda la pantalla (el mapa), la deja abajo, encima de
/// él.
class _TarjetaPosicionada extends StatelessWidget {
  const _TarjetaPosicionada({
    required this.foco,
    required this.tamano,
    required this.relleno,
    required this.child,
  });

  final Rect foco;
  final Size tamano;
  final EdgeInsets relleno;
  final Widget child;

  static const double _altoMinimo = 210;
  static const double _separacion = 16;

  @override
  Widget build(BuildContext context) {
    final abajo = tamano.height - relleno.bottom - foco.bottom;
    final arriba = foco.top - relleno.top;
    final ancho = math.min(tamano.width - 32, 420.0);
    final izquierda = (tamano.width - ancho) / 2;

    if (abajo >= _altoMinimo || (abajo >= arriba && abajo >= 120)) {
      return Positioned(
        left: izquierda,
        width: ancho,
        top: foco.bottom + _separacion,
        child: child,
      );
    }
    if (arriba >= _altoMinimo || arriba >= 120) {
      return Positioned(
        left: izquierda,
        width: ancho,
        bottom: tamano.height - foco.top + _separacion,
        child: child,
      );
    }
    return Positioned(
      left: izquierda,
      width: ancho,
      bottom: relleno.bottom + 24,
      child: child,
    );
  }
}

class _TarjetaPaso extends StatelessWidget {
  const _TarjetaPaso({
    super.key,
    required this.paso,
    required this.indice,
    required this.total,
    required this.onAtras,
    required this.onSiguiente,
  });

  final PasoTour paso;
  final int indice;
  final int total;
  final VoidCallback? onAtras;
  final VoidCallback onSiguiente;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ultimo = indice == total - 1;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColores.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(paso.icono, color: AppColores.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    paso.titulo,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              paso.descripcion,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: 'Paso ${indice + 1} de $total',
              excludeSemantics: true,
              child: Row(
                children: [
                  for (var i = 0; i < total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.only(right: 5),
                      width: i == indice ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == indice
                            ? AppColores.primary
                            : palette.textSecondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Botones en su propia fila (a la derecha): con el tema de la app
            // ocupan más de lo que parece y junto a los puntos no cabían en
            // pantallas angostas.
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (onAtras != null)
                    TextButton(
                      onPressed: onAtras,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Atrás'),
                    ),
                  FilledButton(
                    onPressed: onSiguiente,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppColores.primary,
                      foregroundColor: colorContenidoSobre(AppColores.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      ultimo ? '¡Listo!' : 'Siguiente',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinta el velo con el hueco del foco y el anillo (fijo + onda que late).
class _VeloConFoco extends CustomPainter {
  _VeloConFoco({required this.foco, required this.radio, required this.pulso});

  final Rect foco;
  final double radio;

  /// 0→1 en bucle; 0 fijo sin animaciones.
  final double pulso;

  @override
  void paint(Canvas canvas, Size size) {
    final hueco = RRect.fromRectAndRadius(foco, Radius.circular(radio));
    final velo = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hueco),
    );
    canvas.drawPath(
      velo,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );

    canvas.drawRRect(
      hueco,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColores.primary,
    );

    if (pulso > 0) {
      final onda = hueco.inflate(4 + 10 * pulso);
      canvas.drawRRect(
        onda,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColores.primary.withValues(alpha: 0.55 * (1 - pulso)),
      );
    }
  }

  @override
  bool shouldRepaint(_VeloConFoco old) =>
      old.foco != foco || old.radio != radio || old.pulso != pulso;
}
