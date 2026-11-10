import 'disponibilidad_conductores.dart';

abstract class ConductoresPresentesRepository {
  /// Conductores con señal de vida reciente, en vivo.
  Stream<List<ConductorPresente>> watch();
}
