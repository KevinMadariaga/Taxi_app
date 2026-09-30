// Cobertura de `HistorialConductorViewModel.filtrarPorRango`: la lista de
// Historial de Viajes del conductor ahora muestra solo "Hoy" por defecto
// (antes mostraba TODOS los viajes desde siempre, confundiendo con la
// pantalla separada de ganancias).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/historial_conductor_viewmodel.dart';

/// "Ahora" en hora de Colombia (UTC−5), igual que calcula el viewmodel. No
/// depende de la zona horaria de la máquina: con `DateTime.now()` el test
/// fallaba en el CI (corre en UTC) entre las 19:00 y las 24:00 de Colombia,
/// cuando en UTC ya es el día siguiente.
DateTime _ahoraEnColombia() =>
    DateTime.now().toUtc().subtract(const Duration(hours: 5));

/// Viaje completado a la hora de pared [c] en Colombia. El viewmodel resta
/// 5 h a la marca UTC, así que se guarda esa hora como UTC + 5 h (como
/// vendría de Firestore).
Map<String, dynamic> _viaje(DateTime c) {
  final utc = DateTime.utc(
    c.year,
    c.month,
    c.day,
    c.hour,
    c.minute,
    c.second,
  ).add(const Duration(hours: 5));
  return {'completedAt': Timestamp.fromDate(utc)};
}

void main() {
  final vm = HistorialConductorViewModel();

  test('hoy: solo los viajes completados hoy', () {
    final ahora = _ahoraEnColombia();
    final viajes = [
      _viaje(ahora), // hoy
      _viaje(ahora.subtract(const Duration(days: 1))), // ayer
      _viaje(ahora.subtract(const Duration(days: 10))), // hace 10 días
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.hoy);

    expect(resultado.length, 1);
  });

  test('ayer: solo los viajes completados ayer', () {
    final ahora = _ahoraEnColombia();
    final viajes = [
      _viaje(ahora),
      _viaje(ahora.subtract(const Duration(days: 1))),
      _viaje(ahora.subtract(const Duration(days: 2))),
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.ayer);

    expect(resultado.length, 1);
  });

  test('semana: viajes desde el lunes hasta hoy', () {
    final ahora = _ahoraEnColombia();
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
      _viaje(_ahoraEnColombia()),
      <String, dynamic>{}, // sin completedAt
    ];

    final resultado = vm.filtrarPorRango(viajes, FiltroHistorial.todos);

    expect(resultado.length, 2);
  });

  test('hoy/ayer/semana: un viaje sin fecha de finalización nunca aparece', () {
    final viajes = [<String, dynamic>{}];

    expect(vm.filtrarPorRango(viajes, FiltroHistorial.hoy), isEmpty);
    expect(vm.filtrarPorRango(viajes, FiltroHistorial.ayer), isEmpty);
    expect(vm.filtrarPorRango(viajes, FiltroHistorial.semana), isEmpty);
  });
}
