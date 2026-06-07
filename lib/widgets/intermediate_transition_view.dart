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
}) {
  return Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => IntermediateTransitionView(
        nextBuilder: nextBuilder,
        delay: delay,
        title: title,
        subtitle: subtitle,
        icon: icon,
        clearStackOnNext: clearStackOnNext,
      ),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class IntermediateTransitionView extends StatefulWidget {
  final WidgetBuilder nextBuilder;
  final Duration delay;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool clearStackOnNext;

  const IntermediateTransitionView({
    super.key,
    required this.nextBuilder,
    required this.delay,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.clearStackOnNext = false,
  });

  @override
  State<IntermediateTransitionView> createState() =>
      _IntermediateTransitionViewState();
}

class _IntermediateTransitionViewState extends State<IntermediateTransitionView>
    with TickerProviderStateMixin {
  Timer? _navigationTimer;
  late final AnimationController _pulseController; // anillo + puntos (repite)
  late final AnimationController _entranceController; // entrada (una vez)
  late final Animation<double> _scaleIn;
  late final Animation<double> _fadeIn;
  bool _motionInit = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scaleIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );
    _fadeIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _navigationTimer = Timer(widget.delay, _goNext);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionInit) return;
    _motionInit = true;
    // Respetar la preferencia de reducir movimiento del sistema.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _entranceController.value = 1.0;
    } else {
      _entranceController.forward();
      _pulseController.repeat();
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
    _navigationTimer?.cancel();
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget _animatedDot(int index) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, _) {
        final phase = (_pulseController.value + (index * 0.2)) % 1.0;
        final active = phase < 0.5;
        return Opacity(
          opacity: active ? 1.0 : 0.35,
          child: Transform.scale(
            scale: active ? 1.0 : 0.85,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColores.buttonPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Ícono central con anillo pulsante detrás.
  Widget _buildIcon() {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) {
              final t = _pulseController.value;
              final scale = 1.0 + t * 0.9;
              final opacity = (1.0 - t) * 0.35;
              return Transform.scale(
                scale: scale,
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColores.buttonPrimary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColores.buttonPrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeIn,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(_scaleIn),
              child: Container(
                width: isTablet ? 520 : 320,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildIcon(),
                    const SizedBox(height: 18),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: isTablet ? 24 : 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: isTablet ? 16 : 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _animatedDot(0),
                        const SizedBox(width: 8),
                        _animatedDot(1),
                        const SizedBox(width: 8),
                        _animatedDot(2),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
