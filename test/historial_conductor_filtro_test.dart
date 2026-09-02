// Cobertura de `HistorialConductorViewModel.filtrarPorRango`: la lista de
// Historial de Viajes del conductor ahora muestra solo "Hoy" por defecto
// (antes mostraba TODOS los viajes desde siempre, confundiendo con la
// pantalla separada de ganancias).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/historial_conductor_viewmodel.dart';

Map<String, dynamic> _viaje(DateTime completadoEnColombia) {
  // El viewmodel resta 5h a la marca UTC para obtener hora de Colombia, así
  // que para simular "completado a esta hora en Colombia" hay que guardar
  // la marca sumando esas 5h de vuelta (como si viniera de Firestore).
  final utc = completadoEnColombia.toUtc().add(const Duration(hours: 5));
  return {'completedAt': Timestamp.fromDate(utc)};
}

void main() {
  final vm = HistorialConductorViewModel();

  test('hoy: solo los viajes completados hoy', () {
    final ahora = DateTime.now();
    final viajes = [
      _viaje(ahora), // hoy
      _viaje(ahora.subtract(const Duration(days: 1))), // ayer
      _viaje(ahora.subtract(const Duration(days: 10))), // hace 10 días
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.hoy);

    expect(resultado.length, 1);
  });

  test('ayer: solo los viajes completados ayer', () {
    final ahora = DateTime.now();
    final viajes = [
      _viaje(ahora),
      _viaje(ahora.subtract(const Duration(days: 1))),
      _viaje(ahora.subtract(const Duration(days: 2))),
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.ayer);

    expect(resultado.length, 1);
  });

  test('semana: viajes desde el lunes hasta hoy', () {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
    final viajes = [
      _viaje(hoy), // dentro
      _viaje(inicioSemana), // dentro (borde inicio)
      _viaje(inicioSemana.subtract(const Duration(days: 1))), // fuera
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.semana);

    expect(resultado.length, 2);
  });

  test('todos: no filtra nada, incluso sin fecha de finalización', () {
    final viajes = [
      _viaje(DateTime.now()),
      <String, dynamic>{}, // sin completedAt
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.todos);

    expect(resultado.length, 2);
  });

  test(
    'hoy/ayer/semana: un viaje sin fecha de finalización nunca aparece',
    () {
      final viajes = [<String, dynamic>{}];

      expect(
        vm.filtrarPorRango(viajes, FiltroHistorial.hoy),
        isEmpty,
      );
      expect(
        vm.filtrarPorRango(viajes, FiltroHistorial.ayer),
        isEmpty,
      );
      expect(
        vm.filtrarPorRango(viajes, FiltroHistorial.semana),
        isEmpty,
      );
    },
  );
}
