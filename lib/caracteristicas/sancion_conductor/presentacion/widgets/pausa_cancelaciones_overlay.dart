import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../datos/repositorios/sancion_conductor_repository_impl.dart';
import '../../dominio/entidades/sancion_conductor.dart';
import '../../dominio/repositorios/sancion_conductor_repository.dart';
import '../viewmodels/pausa_cancelaciones_viewmodel.dart';

/// Modal centrado y no descartable mientras el conductor está en pausa por
/// cancelaciones. Va como `Positioned.fill` encima del inicio del conductor:
/// tapa la lista de solicitudes y bloquea los toques. Sin pausa no pinta nada
/// ni intercepta toques. Se retira solo al llegar a 0.
class PausaCancelacionesOverlay extends StatefulWidget {
  const PausaCancelacionesOverlay({
    super.key,
    this.repository,
    this.conductorId,
  });

  /// Inyectables para tests; por defecto Firestore y el usuario actual.
  final SancionConductorRepository? repository;
  final String? conductorId;

  @override
  State<PausaCancelacionesOverlay> createState() =>
      _PausaCancelacionesOverlayState();
}

class _PausaCancelacionesOverlayState extends State<PausaCancelacionesOverlay> {
  late final PausaCancelacionesViewModel _vm;
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _vm = PausaCancelacionesViewModel(
      repository: widget.repository ?? SancionConductorRepositoryImpl(),
      conductorId:
          widget.conductorId ?? FirebaseAuth.instance.currentUser?.uid ?? '',
    )..iniciar();
    _ciclo = AppLifecycleListener(onResume: _vm.recalcular);
  }

  @override
  void dispose() {
    _ciclo.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _vm,
      builder: (context, _) {
        if (!_vm.enPausa) return const SizedBox.shrink();
        final palette = context.palette;
        return Stack(
          children: [
            const ModalBarrier(dismissible: false, color: Colors.black54),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Material(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColores.error.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.timer_outlined,
                              color: AppColores.error,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Pausa por cancelaciones',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Podrás recibir solicitudes en',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _vm.textoRestante,
                            semanticsLabel:
                                '${_vm.restante.inMinutes} minutos restantes',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Cancelaste más de '
                            '${SancionConductor.maxCancelaciones} viajes en '
                            '24 horas. Mientras dure la pausa no te llegarán '
                            'solicitudes nuevas; al terminar vuelves a '
                            'recibirlas automáticamente.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
