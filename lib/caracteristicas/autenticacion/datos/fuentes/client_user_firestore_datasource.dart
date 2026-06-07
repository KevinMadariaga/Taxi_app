import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/modelos/client_user_model.dart';

class ClientUserFirestoreDataSource {
  ClientUserFirestoreDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<ClientUserModel?> getById(String uid) async {
    final doc = await _firestore.collection('usuarios').doc(uid).get();
    if (!doc.exists) return null;
    return ClientUserModel.fromFirestore(
      uid,
      doc.data() ?? <String, dynamic>{},
    );
  }

  Future<ClientUserModel> ensureForGoogle({
    required String uid,
    required String? displayName,
    required String? email,
    String? photoUrl,
  }) async {
    final foto = (photoUrl ?? '').trim();
    final existing = await getById(uid);
    if (existing != null) {
      final patch = <String, dynamic>{};
      if ((existing.email ?? '').isEmpty && (email ?? '').trim().isNotEmpty) {
        patch['email'] = email!.trim();
      }
      // Prellenar foto del proveedor (Gmail) solo si el usuario no tiene una.
      if (existing.fotoUrl.trim().isEmpty && foto.isNotEmpty) {
        patch['foto'] = foto;
      }
      if (patch.isNotEmpty) {
        patch['rol'] = 'cliente';
        await _firestore
            .collection('usuarios')
            .doc(uid)
            .set(patch, SetOptions(merge: true));
      }
      return (await getById(uid)) ?? existing;
    }

    // Separar displayName en nombre + apellido (lo que venga del proveedor).
    final full = (displayName ?? '').trim();
    final partes = full.isEmpty
        ? <String>[]
        : full.split(RegExp(r'\s+'));
    final nombre = partes.isNotEmpty ? partes.first : '';
    final apellido = partes.length > 1 ? partes.sublist(1).join(' ') : '';

    final payload = <String, dynamic>{
      'id': uid,
      'uid': uid,
      'nombre': nombre,
      'apellido': apellido,
      'telefono': '',
      'foto': foto,
      'rol': 'cliente',
      'email': (email ?? '').trim(),
      'isProfileComplete': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('usuarios').doc(uid).set(payload);

    return (await getById(uid)) ??
        ClientUserModel(
          id: uid,
          nombre: nombre,
          apellido: apellido,
          telefono: '',
          fotoUrl: foto,
          rol: 'cliente',
          email: (email ?? '').trim().isEmpty ? null : email!.trim(),
          isProfileComplete: false,
          createdAt: DateTime.now(),
        );
  }

  Future<ClientUserModel> ensureForPhone({
    required String uid,
    required String phoneNumber,
  }) async {
    final existing = await getById(uid);
    if (existing != null) {
      final shouldSetPhone =
          existing.telefono.trim().isEmpty && phoneNumber.trim().isNotEmpty;

      if (shouldSetPhone) {
        await _firestore.collection('usuarios').doc(uid).set({
          'telefono': phoneNumber.trim(),
          'rol': 'cliente',
        }, SetOptions(merge: true));
      }

      return (await getById(uid)) ?? existing;
    }

    final payload = <String, dynamic>{
      'id': uid,
      'uid': uid,
      'nombre': '',
      'apellido': '',
      'telefono': phoneNumber.trim(),
      'foto': '',
      'rol': 'cliente',
      'email': '',
      'isProfileComplete': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('usuarios').doc(uid).set(payload);

    return (await getById(uid)) ??
        ClientUserModel(
          id: uid,
          nombre: '',
          apellido: '',
          telefono: phoneNumber.trim(),
          fotoUrl: '',
          rol: 'cliente',
          email: null,
          isProfileComplete: false,
          createdAt: DateTime.now(),
        );
  }

  Future<void> completeProfile({
    required String uid,
    required String nombre,
    required String apellido,
    required String telefono,
    required String? fotoUrl,
  }) async {
    final safeFotoUrl = (fotoUrl ?? '').trim();

    await _firestore.collection('usuarios').doc(uid).set({
      'id': uid,
      'uid': uid,
      'nombre': nombre.trim(),
      'apellido': apellido.trim(),
      'telefono': telefono.trim(),
      'foto': safeFotoUrl,
      'fotoUrl': FieldValue.delete(),
      'rol': 'cliente',
      'isProfileComplete': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
