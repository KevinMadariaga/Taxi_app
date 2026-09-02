// Cobertura de crear/eliminar favorito en `SeleccionDestinoViewModel`: el
// estado en memoria debe reflejar el cambio sin necesidad de una re-consulta
// (evita el problema de `createdAt == null` en la escritura optimista).

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/casos_uso/eliminar_favorito_usecase.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/casos_uso/guardar_favorito_usecase.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/casos_uso/obtener_favoritos_usecase.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/entidades/ubicacion_entity.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/dominio/repositorios/ubicaciones_repository.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/presentacion/viewmodels/seleccion_destino_viewmodel.dart';

import 'test_helpers/firebase_test_setup.dart';

class _FakeUbicaciones implements UbicacionesRepository {
  final List<UbicacionEntity> favoritosGuardados = [];
  int _autoId = 0;

  @override
  Future<String> guardarFavorito({
    required String nombre,
    required String direccion,
    required LatLng ubicacion,
    required String tipo,
  }) async {
    final id = 'fake-${_autoId++}';
    favoritosGuardados.add(
      UbicacionEntity(
        id: id,
        nombre: nombre,
        direccion: direccion,
        position: ubicacion,
        tipo: tipo,
      ),
    );
    return id;
  }

  @override
  Future<void> eliminarFavorito(String id) async {
    favoritosGuardados.removeWhere((f) => f.id == id);
  }

  @override
  Future<List<UbicacionEntity>> favoritos({int? limit}) async =>
      List.of(favoritosGuardados);

  @override
  Future<List<UbicacionEntity>> todasLasGuardadas() async =>
      List.of(favoritosGuardados);
}

void main() {
  setUpAll(() async {
    await setupFirebaseForTests();
  });

  late _FakeUbicaciones repo;
  late SeleccionDestinoViewModel vm;

  setUp(() {
    repo = _FakeUbicaciones();
    vm = SeleccionDestinoViewModel(
      guardarFavorito: GuardarFavoritoUseCase(repo),
      obtenerFavoritos: ObtenerFavoritosUseCase(repo),
      eliminarFavorito: EliminarFavoritoUseCase(repo),
    );
  });

  test('guardarFavorito inserta el nuevo favorito al frente en memoria', () async {
    final ok = await vm.guardarFavorito(
      nombre: 'Casa',
      ubicacion: const LatLng(8.24, -73.35),
      direccion: 'Cra 1',
    );

    expect(ok, isTrue);
    expect(vm.favoritos, hasLength(1));
    expect(vm.favoritos.first.nombre, 'Casa');
    expect(vm.favoritos.first.id, isNotNull);
  });

  test('eliminarFavorito lo quita de la lista en memoria', () async {
    await vm.guardarFavorito(
      nombre: 'Casa',
      ubicacion: const LatLng(8.24, -73.35),
      direccion: 'Cra 1',
    );
    final id = vm.favoritos.first.id!;

    final ok = await vm.eliminarFavorito(id);

    expect(ok, isTrue);
    expect(vm.favoritos, isEmpty);
  });

  test('eliminarFavorito notifica listeners', () async {
    await vm.guardarFavorito(
      nombre: 'Casa',
      ubicacion: const LatLng(8.24, -73.35),
      direccion: 'Cra 1',
    );
    final id = vm.favoritos.first.id!;

    var notifications = 0;
    vm.addListener(() => notifications++);
    await vm.eliminarFavorito(id);

    expect(notifications, greaterThan(0));
  });
}
