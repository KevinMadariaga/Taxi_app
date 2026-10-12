import '../entidades/sancion_conductor.dart';

abstract class SancionConductorRepository {
  /// Emite [SancionConductor.ninguna] si el conductor no tiene documento.
  Stream<SancionConductor> watch(String conductorId);

  Future<SancionConductor> obtener(String conductorId);
}
