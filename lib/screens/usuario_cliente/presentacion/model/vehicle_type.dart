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

  // Valor a usar como string para Firestore
  String get firestoreKey => name; // 'carro' | 'moto'
}
