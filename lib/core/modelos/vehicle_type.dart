enum VehicleType {
  carro,
  moto;

  String get label => switch (this) {
    VehicleType.carro => 'Carro',
    VehicleType.moto => 'Moto',
  };

  // Precio base en horario diurno
  int get basePriceDia => switch (this) {
    VehicleType.carro => 7000,
    VehicleType.moto => 3000,
  };

  // Precio base en horario nocturno (18:00 – 06:00)
  int get basePriceNoche => switch (this) {
    VehicleType.carro => 10000,
    VehicleType.moto => 5000,
  };

  // Costo variable por kilómetro recorrido, sumado a la tarifa base
  // (basePriceDia/basePriceNoche) — así el valor sugerido del servicio crece
  // con la distancia real del viaje en vez de quedar fijo sin importar qué
  // tan lejos sea el destino.
  int get costoPorKm => switch (this) {
    VehicleType.carro => 600,
    VehicleType.moto => 500,
  };

  // Valor a usar como string para Firestore
  String get firestoreKey => name; // 'carro' | 'moto'
}
