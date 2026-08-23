import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:taxi_app/core/utils/error_reporter.dart';

import '../../dominio/entidades/cliente_actual.dart';
import '../../dominio/repositorios/cliente_repository.dart';

class ClienteRepositoryImpl implements ClienteRepository {
  ClienteRepositoryImpl({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Future<ClienteActual?> obtenerActual() async {
    final user = _auth.currentUser;
    final id = user?.uid.trim();
    if (id == null || id.isEmpty) return null;

    Map<String, dynamic>? doc;
    try {
      final snapshot = await _firestore.collection('usuarios').doc(id).get();
      if (snapshot.exists) doc = snapshot.data();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'cliente_repository_impl');
    }

    return ClienteActual(
      id: id,
      nombre: _resolverNombre(user, doc),
      fotoUrl: _resolverFoto(user, doc),
    );
  }

  // Prioridad: nombre guardado en 'usuarios/{uid}' -> displayName de Auth ->
  // derivado del email (última red de seguridad para no mostrarle "null" al
  // conductor).
  //
  // El doc de Firestore va PRIMERO porque es el único de los dos que se
  // actualiza cuando el cliente edita su perfil (`editar_perfil.dart`
  // escribe `nombre`/`apellido` ahí, nunca llama a
  // `user.updateDisplayName()`) — `displayName` de Auth es el que puso el
  // proveedor (Google/Apple) al registrarse y se queda congelado para
  // siempre. Con el orden viejo, un cliente que editaba su nombre en la app
  // seguía viéndose con el nombre original de Google/Apple en la preview
  // del conductor, aunque Firestore ya tuviera el nombre actualizado.
  String _resolverNombre(User? user, Map<String, dynamic>? doc) {
    // `usuarios/{uid}` guarda nombre y apellido en campos separados (a
    // diferencia de `displayName` de Auth, que ya viene combinado) — sin
    // esto el conductor solo veía el primer nombre del cliente.
    final nombreDoc = _firstNonEmpty(doc, const ['nombre', 'name']);
    final apellidoDoc = _firstNonEmpty(doc, const ['apellido', 'lastName']);
    if (nombreDoc != null) {
      return apellidoDoc != null ? '$nombreDoc $apellidoDoc' : nombreDoc;
    }

    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final desdeDoc = _firstNonEmpty(doc, const ['displayName']);
    if (desdeDoc != null) return desdeDoc;

    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      final parte = email.split('@').first;
      final formateado = parte.replaceAll(RegExp(r'[._\-+]'), ' ');
      final palabras = formateado
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map(
            (w) => w.length == 1
                ? w.toUpperCase()
                : '${w[0].toUpperCase()}${w.substring(1)}',
          )
          .join(' ');
      if (palabras.isNotEmpty) return palabras;
    }

    return 'Cliente';
  }

  // Prioriza la foto que el cliente subió en su perfil (Firestore
  // 'usuarios/{uid}') sobre la del proveedor de Auth (Google/Apple): si el
  // cliente completó su perfil con una foto propia, esa es la que debe
  // verse en la preview del conductor, no la del Gmail cacheada en
  // FirebaseAuth.currentUser.photoURL.
  String? _resolverFoto(User? user, Map<String, dynamic>? doc) {
    final desdeDoc = _firstNonEmpty(doc, const [
      'foto',
      'fotoUrl',
      'photo',
      'photoUrl',
    ]);
    if (desdeDoc != null) return desdeDoc;
    final desdeAuth = user?.photoURL?.trim();
    return (desdeAuth != null && desdeAuth.isNotEmpty) ? desdeAuth : null;
  }

  String? _firstNonEmpty(Map<String, dynamic>? source, List<String> keys) {
    if (source == null) return null;
    for (final key in keys) {
      final raw = source[key]?.toString().trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return null;
  }
}
