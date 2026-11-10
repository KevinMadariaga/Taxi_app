import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

enum TipoViajePendiente {
  /// "Pedir para más tarde": todavía no busca conductor.
  programado,

  /// Sigue buscando sin que el pasajero esté en la pantalla ("Avísame").
  buscandoConAviso,

  /// Apareció conductor mientras el pasajero no estaba mirando.
  conductorEncontrado,
}

/// Un viaje del pasajero que sigue andando mientras él está en el inicio.
@immutable
class ViajePendiente {
  const ViajePendiente({
    required this.id,
    required this.tipo,
    required this.destino,
    this.programadaPara,
    this.tipoVehiculo,
  });

  final String id;
  final TipoViajePendiente tipo;
  final String destino;
  final DateTime? programadaPara;
  final String? tipoVehiculo;

  /// `null` si [estado] no es de los que muestra el inicio: una búsqueda sin
  /// "Avísame" tiene su propia pantalla abierta, y un viaje que se pidió con
  /// la pantalla a la vista ya navegó solo.
  static TipoViajePendiente? tipoDe(String estado, bool conAviso) {
    final e = SolicitudEstado.normalize(estado);
    if (e == SolicitudEstado.programada) return TipoViajePendiente.programado;
    if (!conAviso) return null;
    if (e == SolicitudEstado.buscando) {
      return TipoViajePendiente.buscandoConAviso;
    }
    if (e == SolicitudEstado.asignado) {
      return TipoViajePendiente.conductorEncontrado;
    }
    return null;
  }
}
