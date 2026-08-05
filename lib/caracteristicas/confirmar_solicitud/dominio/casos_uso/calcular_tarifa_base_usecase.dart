import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

/// Tarifa sugerida: base fija según el tipo de vehículo y la hora del día
/// (nocturno 18:00–06:00 cobra más) + costo variable por kilómetro de la
/// ruta ([distanciaKm]) — así el valor sugerido crece con la distancia real
/// del viaje en vez de quedar fijo sin importar qué tan lejos sea el
/// destino. Regla de negocio pura, sin dependencias — [ahora] es inyectable
/// para poder testearla sin mockear `DateTime.now()`.
class CalcularTarifaBaseUseCase {
  const CalcularTarifaBaseUseCase();

  String call(
    VehicleType tipoVehiculo, {
    DateTime? ahora,
    double? distanciaKm,
  }) {
    final hora = (ahora ?? DateTime.now()).hour;
    final esNoche = hora >= 18 || hora < 6;
    final base = esNoche
        ? tipoVehiculo.basePriceNoche
        : tipoVehiculo.basePriceDia;
    final variable = ((distanciaKm ?? 0) * tipoVehiculo.costoPorKm).round();
    final total = base + variable;
    // Redondeo a la centena más cercana: un valor sugerido "limpio"
    // (p.ej. 8.734 -> 8.700) en vez de una cifra con ruido decimal.
    return ((total / 100).round() * 100).toString();
  }
}
