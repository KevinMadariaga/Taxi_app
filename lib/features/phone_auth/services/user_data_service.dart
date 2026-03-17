import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/admin_model.dart';
import '../models/driver_model.dart';

class UserDataService {
  UserDataService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<bool> usuarioExiste(String uid) async {
    final doc = await _firestore.collection('usuarios').doc(uid).get();
    return doc.exists;
  }

  Future<void> guardarUsuarioCliente({
    required String uid,
    required String nombre,
    required String telefono,
    required String foto,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'uid': uid,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'foto': foto,
      'rol': 'cliente',
      'fechaRegistro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Compatibilidad con flujos existentes del proyecto.
    await _firestore.collection('cliente').doc(uid).set({
      'uid': uid,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'foto': foto,
      'rol': 'cliente',
      'fechaRegistro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<Map<String, dynamic>?> streamUsuario(String uid) {
    return _firestore.collection('usuarios').doc(uid).snapshots().map((doc) => doc.data());
  }

  Future<bool> administradorExiste(String uid) async {
    final doc = await _firestore.collection('administradores').doc(uid).get();
    return doc.exists;
  }

  Future<void> guardarAdministrador({
    required String uid,
    required String nombre,
    required String telefono,
    required String foto,
    required String gremio,
  }) async {
    await _firestore.collection('administradores').doc(uid).set({
      'uid': uid,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'foto': foto,
      'gremio': gremio.trim(),
      'rol': 'administrador',
      'fechaRegistro': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<AdminModel?> streamAdministrador(String uid) {
    return _firestore.collection('administradores').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      return AdminModel.fromFirestore(doc.id, data);
    });
  }

  Future<void> guardarConductor({
    required String idConductor,
    required String nombre,
    required String telefono,
    required String placa,
    required String fotoConductor,
    required String fotoVehiculo,
    required String adminId,
  }) async {
    await _firestore.collection('conductores').doc(idConductor).set({
      'idConductor': idConductor,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'placa': placa.trim().toUpperCase(),
      'fotoConductor': fotoConductor,
      'fotoVehiculo': fotoVehiculo,
      'adminId': adminId,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'estado': 'activo',
    });
  }

  Stream<List<DriverModel>> streamConductores({String? adminId}) {
    Query<Map<String, dynamic>> query = _firestore.collection('conductores');
    if (adminId != null && adminId.isNotEmpty) {
      query = query.where('adminId', isEqualTo: adminId);
    }

    return query.orderBy('fechaRegistro', descending: true).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => DriverModel.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);
    });
  }

  Stream<DriverModel?> streamConductor(String conductorId) {
    return _firestore.collection('conductores').doc(conductorId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return DriverModel.fromFirestore(doc.id, doc.data() ?? <String, dynamic>{});
    });
  }
}
