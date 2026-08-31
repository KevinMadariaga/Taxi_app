import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'participante_viaje_entity.dart';

/// Punto de destino del viaje (a donde va el cliente una vez recogido).
class DestinoViajeEntity {
  const DestinoViajeEntity({required this.direccion, required this.ubicacion});

  final String direccion;
  final LatLng? ubicacion;

  bool get tieneUbicacion => ubicacion != null;

  static const DestinoViajeEntity vacio = DestinoViajeEntity(
    direccion: '',
    ubicacion: null,
  );
}

/// Entidad de dominio de un viaje activo — versión unificada y sin
/// dependencia de Firestore de lo que hoy parsean por separado
/// `SolicitudModel`, `DriverTripModel`/`DriverTripParty` y el parseo crudo
/// de `RutaDestinoViewModel`. El mapeo Firestore→entidad vive en
/// `datos/modelos/viaje_model.dart`, no acá.
class ViajeEntity {
  const ViajeEntity({
    required this.id,
    required this.estado,
    required this.cliente,
    required this.conductor,
    required this.destino,
    required this.updatedAt,
    this.valorServicio = 0,
    this.metodoPago = '',
    this.isMoto = false,
    this.esperaIniciadaEn,
  });

  final String id;

  /// Ya normalizado vía `SolicitudEstado.normalize` al momento del parseo.
  final String estado;
  final ParticipanteViajeEntity cliente;
  final ParticipanteViajeEntity conductor;
  final DestinoViajeEntity destino;
  final DateTime? updatedAt;
  final double valorServicio;
  final String metodoPago;
  final bool isMoto;

  /// Ancla de servidor del temporizador de espera (estado `en espera`):
  /// escrita una sola vez por `SolicitudFirestoreDatasource.actualizarEstado`.
  /// `null` en viajes que nunca pasaron por ese estado, o en datos viejos
  /// creados antes de que este campo existiera.
  final DateTime? esperaIniciadaEn;

  bool get hasBothLocations =>
      cliente.tieneUbicacion && conductor.tieneUbicacion;
}
