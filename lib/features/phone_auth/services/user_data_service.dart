import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/firebase_options.dart';

import '../models/admin_model.dart';
import '../models/driver_model.dart';

class ConductorCredentials {
  const ConductorCredentials({required this.email, required this.password});

  final String email;
  final String password;
}

class UpdateConductorCredentialsResult {
  const UpdateConductorCredentialsResult({
    required this.conductorId,
    required this.email,
    required this.password,
  });

  final String conductorId;
  final String email;
  final String password;
}

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
    return _firestore
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.data());
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
    return _firestore.collection('administradores').doc(uid).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      return AdminModel.fromFirestore(doc.id, data);
    });
  }

  Future<String?> obtenerNombreGremioAdministrador({
    required String adminId,
  }) async {
    final safeAdminId = adminId.trim();
    if (safeAdminId.isEmpty) return null;

    final doc = await _firestore
        .collection('administradores')
        .doc(safeAdminId)
        .get();
    if (!doc.exists) return null;

    final data = doc.data() ?? <String, dynamic>{};
    final gremio = (data['gremio'] ?? '').toString().trim();
    if (gremio.isEmpty) return null;
    return gremio;
  }

  Future<ConductorCredentials> generarCredencialesConductor({
    required String nombre,
    String? nombreGremio,
  }) async {
    final random = Random();
    final safeBase = _emailBase(nombre);
    final domain = _emailDomainFromGremio(nombreGremio);

    for (int i = 0; i < 12; i++) {
      final suffix = (1000 + random.nextInt(9000)).toString();
      final email = '$safeBase$suffix@$domain';
      final password = 'Taxi$suffix#${random.nextInt(90) + 10}';

      final existsByCorreo = await _firestore
          .collection('usuarios')
          .where('correo', isEqualTo: email)
          .limit(1)
          .get();
      if (existsByCorreo.docs.isNotEmpty) {
        continue;
      }

      final existsByEmail = await _firestore
          .collection('usuarios')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existsByEmail.docs.isEmpty) {
        return ConductorCredentials(email: email, password: password);
      }
    }

    throw Exception('No se pudieron generar credenciales únicas.');
  }

  String _emailBase(String nombre) {
    final compact = nombre.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '.',
    );
    final normalized = compact.replaceAll(RegExp(r'\.{2,}'), '.');
    final safe = normalized.replaceAll(RegExp(r'^\.|\.$'), '');
    if (safe.isEmpty) return 'conductor';
    return safe.length > 18 ? safe.substring(0, 18) : safe;
  }

  String _emailDomainFromGremio(String? nombreGremio) {
    final compact = (nombreGremio ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '.',
    );
    final normalized = compact.replaceAll(RegExp(r'\.{2,}'), '.');
    final safe = normalized.replaceAll(RegExp(r'^\.|\.$'), '');
    final base = safe.isEmpty
        ? 'cotaxi'
        : (safe.length > 30 ? safe.substring(0, 30) : safe);
    return '$base.com';
  }

  Future<T> _runWithSecondaryAuth<T>(
    Future<T> Function(FirebaseAuth auth) callback,
  ) async {
    final appName = 'driver-admin-${DateTime.now().microsecondsSinceEpoch}';
    final app = await Firebase.initializeApp(
      name: appName,
      options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      final auth = FirebaseAuth.instanceFor(app: app);
      return await callback(auth);
    } finally {
      try {
        await FirebaseAuth.instanceFor(app: app).signOut();
      } catch (_) {}
      await app.delete();
    }
  }

  Future<String> crearConductorAuth({
    required String email,
    required String password,
  }) async {
    return _runWithSecondaryAuth((auth) async {
      final cred = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw Exception(
          'No se pudo crear el usuario autenticado del conductor.',
        );
      }
      return uid;
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
    String? correo,
    String? passwordLogin,
  }) async {
    await _firestore.collection('usuarios').doc(idConductor).set({
      'uid': idConductor,
      'id': idConductor,
      'idConductor': idConductor,
      'tipoUsuario': 'conductor',
      'rol': 'conductor',
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'placa': placa.trim().toUpperCase(),
      'foto': fotoConductor,
      'fotoConductor': FieldValue.delete(),
      'fotoVehiculo': fotoVehiculo,
      'adminId': adminId,
      'estado': 'activo',
      'fechaRegistro': FieldValue.serverTimestamp(),
      if (correo != null && correo.trim().isNotEmpty) 'correo': correo.trim(),
      if (correo != null && correo.trim().isNotEmpty)
        'email': correo.trim().toLowerCase(),
      if (passwordLogin != null && passwordLogin.trim().isNotEmpty)
        'passwordLogin': passwordLogin.trim(),
      if (passwordLogin != null && passwordLogin.trim().isNotEmpty)
        'contrasena': passwordLogin.trim(),
    }, SetOptions(merge: true));
  }

  Future<UpdateConductorCredentialsResult> actualizarCredencialesConductor({
    required String conductorId,
    required String correo,
    required String password,
  }) async {
    final email = correo.trim().toLowerCase();
    final pass = password.trim();

    if (email.isEmpty || !email.contains('@')) {
      throw Exception('Correo inválido.');
    }
    if (pass.length < 6) {
      throw Exception('La contraseña debe tener al menos 6 caracteres.');
    }

    final oldDoc = await _firestore
        .collection('usuarios')
        .doc(conductorId)
        .get();
    final oldData = oldDoc.data() ?? <String, dynamic>{};
    final oldEmail = (oldData['correo'] ?? '').toString().trim();
    final oldPass = (oldData['passwordLogin'] ?? oldData['contrasena'] ?? '')
        .toString()
        .trim();

    String resolvedConductorId = conductorId;

    await _runWithSecondaryAuth((auth) async {
      User? authUser;

      if (oldEmail.isNotEmpty && oldPass.isNotEmpty) {
        try {
          final signIn = await auth.signInWithEmailAndPassword(
            email: oldEmail,
            password: oldPass,
          );
          authUser = signIn.user;
        } catch (_) {}
      }

      if (authUser != null) {
        if ((authUser.email ?? '').toLowerCase() == email) {
          await authUser.updatePassword(pass);
          resolvedConductorId = authUser.uid;
          return;
        }

        // Este SDK no expone updateEmail en User, por lo que migramos
        // credenciales creando una cuenta nueva con el correo actualizado.
        await auth.signOut();
        final created = await auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
        final createdUid = created.user?.uid;
        if (createdUid == null || createdUid.isEmpty) {
          throw Exception('No se pudo actualizar el correo del conductor.');
        }
        resolvedConductorId = createdUid;
        try {
          await authUser.delete();
        } catch (_) {}
        return;
      }

      try {
        final created = await auth.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
        final createdUid = created.user?.uid;
        if (createdUid != null && createdUid.isNotEmpty) {
          resolvedConductorId = createdUid;
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw Exception('El correo ya está en uso por otro usuario.');
        }
        rethrow;
      }
    });

    final merged = <String, dynamic>{
      ...oldData,
      'uid': resolvedConductorId,
      'id': resolvedConductorId,
      'idConductor': resolvedConductorId,
      'correo': email,
      'email': email,
      'passwordLogin': pass,
      'contrasena': pass,
      'rol': 'conductor',
      'tipoUsuario': 'conductor',
      'credencialesActualizadasAt': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('usuarios')
        .doc(resolvedConductorId)
        .set(merged, SetOptions(merge: true));
    if (resolvedConductorId != conductorId) {
      try {
        await _firestore.collection('usuarios').doc(conductorId).delete();
      } catch (_) {}
    }

    return UpdateConductorCredentialsResult(
      conductorId: resolvedConductorId,
      email: email,
      password: pass,
    );
  }

  Future<void> actualizarEstadoConductor({
    required String conductorId,
    required bool activo,
  }) async {
    final estado = activo ? 'activo' : 'inactivo';
    await _firestore.collection('usuarios').doc(conductorId).set({
      'estado': estado,
      'estadoActualizadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> actualizarPerfilConductor({
    required String conductorId,
    String? nombre,
    String? telefono,
    String? placa,
    String? fotoConductor,
    String? fotoVehiculo,
  }) async {
    final updates = <String, dynamic>{
      'perfilActualizadoAt': FieldValue.serverTimestamp(),
    };
    if (nombre != null && nombre.trim().isNotEmpty) {
      updates['nombre'] = nombre.trim();
    }
    if (telefono != null && telefono.trim().isNotEmpty) {
      updates['telefono'] = telefono.trim();
    }
    if (placa != null && placa.trim().isNotEmpty) {
      updates['placa'] = placa.trim().toUpperCase();
    }
    if (fotoConductor != null && fotoConductor.trim().isNotEmpty) {
      updates['foto'] = fotoConductor.trim();
      updates['fotoConductor'] = FieldValue.delete();
    }
    if (fotoVehiculo != null && fotoVehiculo.trim().isNotEmpty) {
      updates['fotoVehiculo'] = fotoVehiculo.trim();
    }

    await _firestore
        .collection('usuarios')
        .doc(conductorId)
        .set(updates, SetOptions(merge: true));
  }

  Future<void> actualizarPerfilAdministrador({
    required String adminId,
    String? nombre,
    String? telefono,
    String? foto,
    String? gremioFoto,
  }) async {
    final updates = <String, dynamic>{
      'perfilActualizadoAt': FieldValue.serverTimestamp(),
    };
    if (nombre != null && nombre.trim().isNotEmpty) {
      updates['nombre'] = nombre.trim();
    }
    if (telefono != null && telefono.trim().isNotEmpty) {
      updates['telefono'] = telefono.trim();
    }
    if (foto != null && foto.trim().isNotEmpty) {
      updates['foto'] = foto.trim();
    }
    if (gremioFoto != null && gremioFoto.trim().isNotEmpty) {
      updates['gremioFoto'] = gremioFoto.trim();
    }

    await _firestore
        .collection('administradores')
        .doc(adminId)
        .set(updates, SetOptions(merge: true));
  }

  Future<void> eliminarAdministradorData(String adminId) async {
    await _firestore.collection('administradores').doc(adminId).delete();
  }

  Stream<List<DriverModel>> streamConductores({String? adminId}) {
    final query = _firestore
        .collection('usuarios')
        .where('rol', isEqualTo: 'conductor');

    return query.snapshots().map((snapshot) {
      final docs = snapshot.docs.where((doc) {
        if (adminId == null || adminId.isEmpty) return true;
        final data = doc.data();
        return (data['adminId'] ?? '').toString() == adminId;
      });

      final conductores = docs
          .map((doc) => DriverModel.fromFirestore(doc.id, doc.data()))
          .toList(growable: false);

      final ordenados = conductores.toList(growable: false)
        ..sort((a, b) {
          final aMs = a.fechaRegistro?.millisecondsSinceEpoch ?? 0;
          final bMs = b.fechaRegistro?.millisecondsSinceEpoch ?? 0;
          return bMs.compareTo(aMs);
        });

      return ordenados;
    });
  }

  Stream<DriverModel?> streamConductor(String conductorId) {
    return _firestore.collection('usuarios').doc(conductorId).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      final data = doc.data() ?? <String, dynamic>{};
      final role = (data['rol'] ?? data['tipoUsuario'] ?? '')
          .toString()
          .toLowerCase();
      if (role != 'conductor') return null;
      return DriverModel.fromFirestore(doc.id, data);
    });
  }
}
