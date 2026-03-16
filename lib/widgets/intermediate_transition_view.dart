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
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => IntermediateTransitionView(
        nextBuilder: nextBuilder,
        delay: delay,
        title: title,
        subtitle: subtitle,
        icon: icon,
        clearStackOnNext: clearStackOnNext,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
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
    with SingleTickerProviderStateMixin {
  Timer? _navigationTimer;
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _navigationTimer = Timer(widget.delay, _goNext);
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
    _dotsController.dispose();
    super.dispose();
  }

  Widget _animatedDot(int index) {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (_, __) {
        final phase = (_dotsController.value + (index * 0.2)) % 1.0;
        final active = phase < 0.5;
        final opacity = active ? 1.0 : 0.35;
        final scale = active ? 1.0 : 0.85;

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
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

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 1000;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: SafeArea(
        child: Center(
          child: Container(
            width: isTablet ? 520 : 320,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColores.buttonPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 20),
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
    );
  }
}
