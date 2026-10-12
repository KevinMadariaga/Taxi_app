import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';

/// Cancelación desde el lado del conductor. `cancelledBy: 'conductor'` es lo
/// que lee la Cloud Function para avisarle al cliente "El conductor canceló"
/// y para contar la cancelación en la pausa por cancelaciones.
class CancelarViajeConductorUseCase {
  CancelarViajeConductorUseCase(this._repository);

  final ViajeRepository _repository;

  Future<void> call({required String viajeId, required String motivo}) {
    return _repository.cancelar(
      viajeId: viajeId,
      canceladoPor: 'conductor',
      motivo: motivo,
    );
  }
}
