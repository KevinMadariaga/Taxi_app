import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';

/// Propaga un cambio de perfil del conductor (nombre/foto/placa/fotoVehiculo,
/// hecho en `editar_perfil.dart`) hacia la copia congelada que vive en
/// `solicitudes/{viajeId}.conductor` — la única que el cliente puede leer
/// (`firestore.rules` no le permite leer `usuarios/{uid}` de otro usuario).
///
/// A diferencia de [ActualizarEstadoViajeUseCase], no toca `estado`.
class ActualizarInfoConductorEnViajeUseCase {
  ActualizarInfoConductorEnViajeUseCase(this._repository);

  final ViajeRepository _repository;

  Future<void> call({
    required String viajeId,
    required Map<String, dynamic> datosConductor,
  }) {
    return _repository.actualizarInfoConductor(
      viajeId: viajeId,
      datosConductor: datosConductor,
    );
  }
}
