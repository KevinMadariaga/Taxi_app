import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../datos/conductores_presentes_repository_impl.dart';
import '../dominio/conductores_presentes_repository.dart';
import '../dominio/disponibilidad_conductores.dart';
import 'tarjeta_aviso_disponibilidad.dart';

/// Aviso antes de pedir el viaje: escucha quién está conectado cerca de
/// [lat]/[lng] y no pinta nada si hay conductores de sobra. Si falla la
/// lectura tampoco: no saber la disponibilidad no debe estorbar el pedido.
class AvisoDisponibilidadEnVivo extends StatefulWidget {
  const AvisoDisponibilidadEnVivo({
    super.key,
    required this.lat,
    required this.lng,
    required this.esMoto,
    required this.onCambiarVehiculo,
    this.repositorio,
  });

  final double lat;
  final double lng;
  final bool esMoto;
  final ValueChanged<bool> onCambiarVehiculo;
  final ConductoresPresentesRepository? repositorio;

  @override
  State<AvisoDisponibilidadEnVivo> createState() =>
      _AvisoDisponibilidadEnVivoState();
}

class _AvisoDisponibilidadEnVivoState extends State<AvisoDisponibilidadEnVivo> {
  StreamSubscription<List<ConductorPresente>>? _sub;
  Timer? _reloj;
  List<ConductorPresente>? _conductores;

  @override
  void initState() {
    super.initState();
    try {
      _sub = (widget.repositorio ?? ConductoresPresentesRepositoryImpl())
          .watch()
          .listen(
            (lista) {
              if (mounted) setState(() => _conductores = lista);
            },
            onError: (Object e, StackTrace st) =>
                ErrorReporter.report(e, st, reason: 'aviso_disponibilidad'),
          );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'aviso_disponibilidad');
    }
    // Los snapshots solo llegan cuando alguien escribe: sin esto, el último
    // conductor en irse seguiría contando con la pantalla abierta.
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conductores = _conductores;
    // Sin datos todavía no se dice nada: mostrar "no hay conductores" durante
    // la carga asustaría a alguien que sí tiene.
    if (conductores == null) return const SizedBox.shrink();
    final aviso = avisoDisponibilidad(
      calcularDisponibilidad(
        conductores,
        lat: widget.lat,
        lng: widget.lng,
        ahora: DateTime.now(),
      ),
      esMoto: widget.esMoto,
    );
    if (aviso == null) return const SizedBox.shrink();
    return Padding(
      // Arriba: sin aviso no deja hueco.
      padding: const EdgeInsets.only(top: 8),
      child: TarjetaAvisoDisponibilidad(
        aviso: aviso,
        onCambiarVehiculo: widget.onCambiarVehiculo,
      ),
    );
  }
}
