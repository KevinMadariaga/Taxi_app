// Regresión del autocompletado de destino.
//
// El caso de uso combinaba las dos fuentes (ubicaciones guardadas + Google
// Places) con un `Future.wait` pelado. Como `Future.wait` falla en conjunto si
// falla cualquiera de sus futures, un error en las guardadas — que ocurría
// SIEMPRE, porque la query a `ubicaciones` no estaba acotada por `userId` y
// las reglas la rechazaban con `permission-denied` — descartaba también los
// resultados de Places que sí habían llegado. Efecto para el usuario: escribía
// un destino y no veía ni una sugerencia.
//
// Estos tests fijan que cada fuente degrada de forma independiente.

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/casos_uso/buscar_destinos_usecase.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/entidades/ubicacion_entity.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/repositorios/lugares_repository.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/repositorios/ubicaciones_repository.dart';

import 'test_helpers/firebase_test_setup.dart';

/// Dentro del radio de Ocaña que aplica el caso de uso a las guardadas.
final _enOcana = UbicacionEntity(
  nombre: 'Casa',
  direccion: 'Carrera 10 Ocaña',
  position: BuscarDestinosUseCase.ocanaCenter,
);

const _lejos = UbicacionEntity(
  nombre: 'Bogota',
  direccion: 'Calle 100 Bogota',
  position: LatLng(4.7110, -74.0721),
);

class _FakeUbicaciones implements UbicacionesRepository {
  _FakeUbicaciones({this.guardadas = const [], this.error});

  final List<UbicacionEntity> guardadas;
  final Object? error;

  @override
  Future<List<UbicacionEntity>> todasLasGuardadas() async {
    if (error != null) throw error!;
    return guardadas;
  }

  @override
  Future<List<UbicacionEntity>> favoritosPorTipo(String tipo, {int? limit}) async => const [];

  @override
  Future<void> guardarFavorito({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  }) async {}
}

class _FakeLugares implements LugaresRepository {
  _FakeLugares({this.resultados = const [], this.error});

  final List<UbicacionEntity> resultados;
  final Object? error;

  @override
  Future<List<UbicacionEntity>> buscar(String query) async {
    if (error != null) throw error!;
    return resultados;
  }

  @override
  Future<UbicacionEntity?> detalle(String placeId) async => null;
}

void main() {
  setUpAll(() async {
    // ErrorReporter -> Crashlytics necesita Firebase inicializado.
    await setupFirebaseForTests();
  });

  const places = UbicacionEntity(
    nombre: 'Parque principal',
    direccion: 'Ocaña',
    placeId: 'p1',
  );

  test('si fallan las guardadas, los resultados de Places sobreviven', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(error: Exception('permission-denied')),
      _FakeLugares(resultados: const [places]),
    );

    final resultado = await useCase('parque');

    expect(resultado.map((u) => u.nombre), ['Parque principal']);
  });

  test('si falla Places, las guardadas sobreviven', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(guardadas: [_enOcana]),
      _FakeLugares(error: Exception('timeout')),
    );

    final resultado = await useCase('casa');

    expect(resultado.map((u) => u.nombre), ['Casa']);
  });

  test('si fallan las dos fuentes devuelve vacío en vez de lanzar', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(error: Exception('boom')),
      _FakeLugares(error: Exception('boom')),
    );

    await expectLater(useCase('algo'), completion(isEmpty));
  });

  test('combina ambas fuentes cuando las dos responden', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(guardadas: [_enOcana]),
      _FakeLugares(resultados: const [places]),
    );

    final resultado = await useCase('a');

    expect(resultado.map((u) => u.nombre), ['Casa', 'Parque principal']);
  });

  test('descarta guardadas fuera del radio de Ocaña', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(guardadas: [_enOcana, _lejos]),
      _FakeLugares(),
    );

    final resultado = await useCase('a');

    expect(resultado.map((u) => u.nombre), ['Casa']);
  });

  test('query vacía no consulta ninguna fuente', () async {
    final useCase = BuscarDestinosUseCase(
      _FakeUbicaciones(error: Exception('no debería llamarse')),
      _FakeLugares(error: Exception('no debería llamarse')),
    );

    expect(await useCase('   '), isEmpty);
  });
}
