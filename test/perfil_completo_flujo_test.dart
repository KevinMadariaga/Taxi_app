// "Completa tu perfil" solo debe aparecer mientras el perfil esté a medias:
// alta nueva → incompleto; tras completarlo, un nuevo login va al home.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/fuentes/client_user_firestore_datasource.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/auth_identity_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';

/// Repositorio mínimo sobre el datasource REAL con Firestore en memoria:
/// lo que se prueba es lo que queda escrito y cómo se relee.
class _Repo implements ClientAuthRepository {
  _Repo(this.ds);
  final ClientUserFirestoreDataSource ds;

  @override
  Future<AuthIdentityEntity?> signInWithGoogle() async =>
      const AuthIdentityEntity(uid: 'u1', displayName: 'Laura Gómez');

  @override
  Future<ClientUserEntity> ensureClientUserForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
  }) => ds.ensureForGoogle(
    uid: uid,
    displayName: displayName,
    email: email,
    photoUrl: photoUrl,
  );

  @override
  Future<void> syncAuthDisplayName(String nombreCompleto) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late FakeFirebaseFirestore db;
  late ClientUserFirestoreDataSource ds;
  late SignInGoogleClientUseCase login;

  setUp(() {
    db = FakeFirebaseFirestore();
    ds = ClientUserFirestoreDataSource(firestore: db);
    login = SignInGoogleClientUseCase(_Repo(ds));
  });

  test('alta nueva va a completar perfil', () async {
    final r = await login();
    expect(r.destination, AuthFlowDestination.completeProfile);
    final doc = (await db.doc('usuarios/u1').get()).data()!;
    expect(doc['isProfileComplete'], false);
    expect(doc['rol'], 'cliente');
  });

  test('sin completar, volver a iniciar sesión sigue en completar perfil', () async {
    await login();
    final r = await login();
    expect(r.destination, AuthFlowDestination.completeProfile);
  });

  test('perfil completado queda guardado y el re-login va al home', () async {
    await login();
    await ds.completeProfile(
      uid: 'u1',
      nombre: 'Laura',
      apellido: 'Gómez',
      telefono: '3001234567',
      fotoUrl: 'https://x/foto.webp',
    );

    final doc = (await db.doc('usuarios/u1').get()).data()!;
    expect(doc['isProfileComplete'], true);
    expect(doc['foto'], 'https://x/foto.webp');
    expect(doc['telefono'], '3001234567');
    expect(doc.containsKey('fotoUrl'), isFalse);

    final r = await login();
    expect(r.destination, AuthFlowDestination.clientHome);
    // El re-login no reabre el perfil ni pisa lo guardado.
    final despues = (await db.doc('usuarios/u1').get()).data()!;
    expect(despues['isProfileComplete'], true);
    expect(despues['nombre'], 'Laura');
  });

  test('marcado completo pero sin foto vuelve a completar perfil '
      '(mismo criterio que el cold-start)', () async {
    await db.doc('usuarios/u1').set({
      'nombre': 'Laura',
      'apellido': 'Gómez',
      'rol': 'cliente',
      'isProfileComplete': true,
      'foto': '',
    });
    final r = await login();
    expect(r.destination, AuthFlowDestination.completeProfile);
  });
}
