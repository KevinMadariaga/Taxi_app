import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

Future<void> navigateWithIntermediateLoader({
  required BuildContext context,
  required WidgetBuilder nextBuilder,
  Duration delay = const Duration(seconds: 2),
  String title = 'Conductor encontrado',
  String subtitle = 'Preparando tu ruta y detalles del viaje...',
  IconData icon = Icons.local_taxi,
  bool clearStackOnNext = false,
  Color accentColor = AppColores.buttonPrimary,
  bool drawCheck = true,
  VoidCallback? onAfterDelay,
}) {
  return Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => IntermediateTransitionView(
        nextBuilder: nextBuilder,
        delay: delay,
        title: title,
        subtitle: subtitle,
        icon: icon,
        clearStackOnNext: clearStackOnNext,
        accentColor: accentColor,
        drawCheck: drawCheck,
        onAfterDelay: onAfterDelay,
      ),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}

/// Pantalla intermedia animada que se muestra al pasar a la ruta cuando la
/// solicitud queda 'asignado'. Cliente: "Conductor encontrado".
/// Conductor: "Servicio aceptado". Animación: check que se dibuja dentro de un
/// círculo con ondas concéntricas, y textos que aparecen escalonados.
class IntermediateTransitionView extends StatefulWidget {
  final WidgetBuilder nextBuilder;
  final Duration delay;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool clearStackOnNext;
  final Color accentColor;
  final bool drawCheck;
  final VoidCallback? onAfterDelay;

  const IntermediateTransitionView({
    super.key,
    required this.nextBuilder,
    required this.delay,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.clearStackOnNext = false,
    this.accentColor = AppColores.buttonPrimary,
    this.drawCheck = true,
    this.onAfterDelay,
  });

  @override
  State<IntermediateTransitionView> createState() =>
      _IntermediateTransitionViewState();
}

class _IntermediateTransitionViewState extends State<IntermediateTransitionView>
    with TickerProviderStateMixin {
  Timer? _navTimer;
  late final AnimationController _entrance; // una vez
  late final AnimationController _ripple; // repite

  late final Animation<double> _circleScale;
  late final Animation<double> _checkProgress;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;

  bool _motionInit = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _circleScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
    );
    _checkProgress = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.4, 0.85, curve: Curves.easeInOut),
    );
    _textFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );
    _textSlide = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _navTimer = Timer(widget.delay, () {
      widget.onAfterDelay?.call();
      _goNext();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInit) return;
    _motionInit = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _entrance.value = 1.0;
    } else {
      _entrance.forward();
      _ripple.repeat();
    }
  }

  void _goNext() {
    if (!mounted) return;
    if (widget.clearStackOnNext) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: widget.nextBuilder),
        (route) => false,
      );
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: widget.nextBuilder));
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _entrance.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 1000;
    final accent = widget.accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Círculo + ondas + check (zona animada aislada en su capa).
                RepaintBoundary(
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ondas concéntricas.
                        AnimatedBuilder(
                          animation: _ripple,
                          builder: (_, _) => CustomPaint(
                            size: const Size(160, 160),
                            painter: _RipplePainter(
                              progress: _ripple.value,
                              color: accent,
                            ),
                          ),
                        ),
                        // Círculo con check (éxito) o ícono (ej. cancelado).
                        ScaleTransition(
                          scale: _circleScale,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: widget.drawCheck
                                ? AnimatedBuilder(
                                    animation: _checkProgress,
                                    builder: (_, _) => CustomPaint(
                                      painter: _CheckPainter(
                                        progress: _checkProgress.value,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    widget.icon,
                                    color: Colors.white,
                                    size: 44,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _entrance,
                  builder: (_, child) => Opacity(
                    opacity: _textFade.value.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: child,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 26 : 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                    ],
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

/// Dibuja un checkmark progresivo (0..1) dentro del cuadro.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final p1 = Offset(size.width * 0.28, size.height * 0.52);
    final p2 = Offset(size.width * 0.44, size.height * 0.67);
    final p3 = Offset(size.width * 0.74, size.height * 0.35);

    final seg1 = (p2 - p1).distance;
    final seg2 = (p3 - p2).distance;
    final total = seg1 + seg2;
    final drawn = total * progress;

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (drawn <= seg1) {
      final t = seg1 == 0 ? 1.0 : drawn / seg1;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = seg2 == 0 ? 1.0 : (drawn - seg1) / seg2;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// Dibuja 2 ondas concéntricas que se expanden y desvanecen.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const minR = 48.0;
    final maxR = size.width / 2;

    for (int i = 0; i < 2; i++) {
      final t = (progress + i * 0.5) % 1.0;
      final radius = minR + (maxR - minR) * t;
      final opacity = (1.0 - t) * 0.35;
      if (opacity <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress || old.color != color;
}
