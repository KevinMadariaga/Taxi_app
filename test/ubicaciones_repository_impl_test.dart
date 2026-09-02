// Cobertura de `UbicacionesRepositoryImpl` contra `fake_cloud_firestore` —
// fija el comportamiento que motivó todo el trabajo de favoritos: antes cada
// `guardarFavorito` escribía dos documentos sin correlación (uno en
// `usuarios/{uid}/favoritos`, otro en el espejo plano `ubicaciones`), y
// `ubicaciones` no se podía borrar por reglas — un favorito "borrado" seguía
// apareciendo para siempre en el autocompletado de destino.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/caracteristicas/seleccion_destino/datos/repositorios/ubicaciones_repository_impl.dart';
import 'package:taxi_app/core/services/favoritos_service.dart';

const _uid = 'user-1';
const _punto = LatLng(8.24, -73.35);

UbicacionesRepositoryImpl _repo(FakeFirebaseFirestore fs) {
  final auth = MockFirebaseAuth(
    mockUser: MockUser(uid: _uid, isAnonymous: false),
    signedIn: true,
  );
  return UbicacionesRepositoryImpl(
    favoritosService: FavoritosService(firestore: fs),
    auth: auth,
  );
}

void main() {
  test('guardarFavorito no escribe nada en la colección ubicaciones', () async {
    final fs = FakeFirebaseFirestore();
    final repo = _repo(fs);

    await repo.guardarFavorito(
      nombre: 'Casa',
      direccion: 'Cra 1 # 2-3',
      ubicacion: _punto,
      tipo: 'Favorito',
    );

    final ubicaciones = await fs.collection('ubicaciones').get();
    expect(ubicaciones.docs, isEmpty);

    final favoritos = await fs
        .collection('usuarios')
        .doc(_uid)
        .collection('favoritos')
        .get();
    expect(favoritos.docs, hasLength(1));
  });

  test('guardarFavorito devuelve el id del documento creado', () async {
    final fs = FakeFirebaseFirestore();
    final repo = _repo(fs);

    final id = await repo.guardarFavorito(
      nombre: 'Trabajo',
      direccion: 'Cra 5 # 6-7',
      ubicacion: _punto,
      tipo: 'Favorito',
    );

    final doc = await fs
        .collection('usuarios')
        .doc(_uid)
        .collection('favoritos')
        .doc(id)
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['nombre'], 'Trabajo');
  });

  test('favoritos() propaga el id de cada documento', () async {
    final fs = FakeFirebaseFirestore();
    final repo = _repo(fs);
    final id = await repo.guardarFavorito(
      nombre: 'Casa',
      direccion: 'Cra 1',
      ubicacion: _punto,
      tipo: 'Favorito',
    );

    final favoritos = await repo.favoritos();
    expect(favoritos, hasLength(1));
    expect(favoritos.single.id, id);
  });

  test('favoritos() conserva documentos sin GeoPoint (position == null)', () async {
    final fs = FakeFirebaseFirestore();
    await fs
        .collection('usuarios')
        .doc(_uid)
        .collection('favoritos')
        .add({'nombre': 'Sin ubicación', 'direccion': '', 'tipo': 'Favorito'});
    final repo = _repo(fs);

    final favoritos = await repo.favoritos();
    expect(favoritos, hasLength(1));
    expect(favoritos.single.position, isNull);
  });

  test('favoritos() incluye documentos legacy sin campo tipo', () async {
    final fs = FakeFirebaseFirestore();
    await fs.collection('usuarios').doc(_uid).collection('favoritos').add({
      'nombre': 'Legacy',
      'direccion': 'Calle legacy',
      'ubicacion': const GeoPoint(8.24, -73.35),
    });
    final repo = _repo(fs);

    final favoritos = await repo.favoritos();
    expect(favoritos, hasLength(1));
    expect(favoritos.single.nombre, 'Legacy');
  });

  test('eliminarFavorito borra solo el documento correcto', () async {
    final fs = FakeFirebaseFirestore();
    final repo = _repo(fs);
    final id1 = await repo.guardarFavorito(
      nombre: 'A',
      direccion: 'A',
      ubicacion: _punto,
      tipo: 'Favorito',
    );
    final id2 = await repo.guardarFavorito(
      nombre: 'B',
      direccion: 'B',
      ubicacion: _punto,
      tipo: 'Favorito',
    );

    await repo.eliminarFavorito(id1);

    final restantes = await repo.favoritos();
    expect(restantes, hasLength(1));
    expect(restantes.single.id, id2);
  });

  test('todasLasGuardadas() lee la subcolección de favoritos, no ubicaciones', () async {
    final fs = FakeFirebaseFirestore();
    final repo = _repo(fs);
    await repo.guardarFavorito(
      nombre: 'Casa',
      direccion: 'Cra 1',
      ubicacion: _punto,
      tipo: 'Favorito',
    );
    // Documento en el espejo legacy: no debe aparecer, confirma que la
    // fuente es la subcolección, no la colección raíz.
    await fs.collection('ubicaciones').add({
      'userId': _uid,
      'nombre': 'Fantasma del espejo viejo',
      'direccion': '',
    });

    final todas = await repo.todasLasGuardadas();
    expect(todas, hasLength(1));
    expect(todas.single.nombre, 'Casa');
  });
}
