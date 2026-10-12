import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../dominio/entidades/sancion_conductor.dart';
import '../../dominio/repositorios/sancion_conductor_repository.dart';

/// Cuenta regresiva de la pausa por cancelaciones. El tiempo restante sale
/// SIEMPRE de `bloqueadoHasta` contra el reloj, no de un contador propio: si
/// la app estuvo cerrada o en segundo plano, al volver muestra lo que de
/// verdad falta (o nada, si ya venció).
class PausaCancelacionesViewModel extends ChangeNotifier {
  PausaCancelacionesViewModel({
    required SancionConductorRepository repository,
    required this.conductorId,
    DateTime Function()? now,
  }) : _repository = repository,
       _now = now ?? DateTime.now;

  final SancionConductorRepository _repository;
  final String conductorId;
  final DateTime Function() _now;

  SancionConductor _sancion = SancionConductor.ninguna;
  Duration restante = Duration.zero;
  bool get enPausa => restante > Duration.zero;

  StreamSubscription<SancionConductor>? _sub;
  Timer? _tick;
  bool _disposed = false;

  void iniciar() {
    if (conductorId.isEmpty) return;
    _sub = _repository.watch(conductorId).listen(
      (s) {
        _sancion = s;
        recalcular();
      },
      // Sin poder leer la sanción no se bloquea la pantalla: las reglas
      // y el servidor igual impiden aceptar/recibir durante la pausa.
      onError: (_) {},
    );
  }

  /// Llamar también al volver a primer plano.
  void recalcular() {
    if (_disposed) return;
    restante = _sancion.restante(_now());
    if (enPausa) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => recalcular());
    } else {
      _tick?.cancel();
      _tick = null;
    }
    notifyListeners();
  }

  /// `mm:ss` del tiempo restante, redondeando hacia arriba el segundo en curso.
  String get textoRestante {
    final s = (restante.inMilliseconds / 1000).ceil();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
