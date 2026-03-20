import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/data/models/client_auth/client_user_model.dart';

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
  }) async {
    final existing = await getById(uid);
    if (existing != null) {
      final hasEmail = (existing.email ?? '').isNotEmpty;
      if (!hasEmail && (email ?? '').trim().isNotEmpty) {
        await _firestore.collection('usuarios').doc(uid).set({
          'email': email!.trim(),
          'rol': 'cliente',
        }, SetOptions(merge: true));
      }
      return (await getById(uid)) ?? existing;
    }

    final nombre = (displayName ?? '').trim();
    final payload = <String, dynamic>{
      'id': uid,
      'uid': uid,
      'nombre': nombre,
      'apellido': '',
      'telefono': '',
      'foto': '',
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
          apellido: '',
          telefono: '',
          fotoUrl: '',
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
