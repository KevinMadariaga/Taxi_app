import 'dart:developer' as developer;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:taxi_app/firebase_options.dart';

import '../models/admin_model.dart';
import '../models/driver_model.dart';
import 'package:taxi_app/core/services/admin_fcm_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

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

  /// Lectura puntual (no-stream) del documento `usuarios/{uid}`. Antes
  /// `CompletarRegistroConductorView` y `activacion_servicio_view` leían
  /// Firestore directo desde el widget.
  Future<Map<String, dynamic>?> getUsuario(String uid) async {
    final doc = await _firestore.collection('usuarios').doc(uid).get();
    return doc.data();
  }

  /// Resuelve el perfil de `uid` con fallback a colecciones legacy
  /// (`conductores`/`conductor`/`cliente`) cuando `usuarios/{uid}` no tiene
  /// nombre — antes esta lógica de resolución vivía en `PaginaPerfilUsuario`
  /// (widget de UI). `usuarios` tiene prioridad: los fallback solo rellenan
  /// campos ausentes. No incluye el fallback final a Firebase Auth
  /// (displayName/photoURL) — eso es responsabilidad de la capa de Auth, no
  /// de este repositorio de Firestore.
  Future<Map<String, dynamic>> getPerfilConFallback(String uid) async {
    final data = <String, dynamic>{};

    try {
      final snap = await _firestore.collection('usuarios').doc(uid).get();
      final d = snap.data();
      if (snap.exists && d != null) data.addAll(d);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'UserDataService.getPerfilConFallback');
    }

    final faltaNombre = (data['nombre'] ?? '').toString().trim().isEmpty;
    if (faltaNombre) {
      for (final col in const ['conductores', 'conductor', 'cliente']) {
        try {
          final s = await _firestore.collection(col).doc(uid).get();
          final d = s.data();
          if (s.exists && d != null) {
            for (final e in d.entries) {
              data.putIfAbsent(e.key, () => e.value);
            }
            break;
          }
        } catch (e, st) {
          ErrorReporter.report(
            e,
            st,
            reason: 'UserDataService.getPerfilConFallback',
          );
        }
      }
    }

    return data;
  }

  /// Guarda foto + placa de un tipo de vehículo (carro/moto) del conductor
  /// SIN cambiar cuál está activo. Antes `CambiarVehiculoView` escribía a
  /// Firestore directo desde el widget.
  Future<void> guardarVehiculo({
    required String uid,
    required String tipo,
    required String foto,
    required String placa,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'vehiculos': {
        tipo: {'foto': foto, 'placa': placa},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Guarda foto + placa de un tipo de vehículo Y lo activa (campos raíz
  /// `tipoVehiculo`/`fotoVehiculo`/`placa`, leídos por el resto de la app).
  Future<void> activarVehiculo({
    required String uid,
    required String tipo,
    required String foto,
    required String placa,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'vehiculos': {
        tipo: {'foto': foto, 'placa': placa},
      },
      'tipoVehiculo': tipo,
      'fotoVehiculo': foto,
      'placa': placa,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Merge genérico de campos editados desde `PaginaPerfilUsuario` /
  /// `EditarPerfilScreen`.
  Future<void> actualizarDatosUsuario(
    String uid,
    Map<String, dynamic> datos,
  ) async {
    await _firestore
        .collection('usuarios')
        .doc(uid)
        .set(datos, SetOptions(merge: true));
  }

  /// Guarda la lista de contactos de emergencia del usuario (cliente o
  /// conductor, ambos viven en `usuarios/{uid}`). Antes `SeguridadView` /
  /// `SeguridadConductorView` los guardaban solo en memoria del State y se
  /// perdían al salir de la pantalla.
  Future<void> guardarContactosEmergencia({
    required String uid,
    required List<String> contactos,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'contactosEmergencia': contactos,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Lee los contactos de emergencia guardados de `usuarios/{uid}`.
  Future<List<String>> obtenerContactosEmergencia(String uid) async {
    final data = await getUsuario(uid);
    final raw = data?['contactosEmergencia'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Cambia el rol guardado a conductor (el usuario ya tiene placa + foto de
  /// vehículo registradas). Fire-and-forget en el llamador, igual que antes.
  Future<void> cambiarRolAConductor(String uid) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'rol': 'conductor',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Vuelve el rol a cliente. A propósito NO toca `solicitudConductor`: si
  /// el usuario había pedido activar el servicio, esa solicitud debe seguir
  /// visible para el admin (pestaña de conductores + badge de pendientes en
  /// `admin_home_screen.dart`) aunque el usuario haya vuelto a cliente antes
  /// de que lo resuelvan. Solo un admin la cierra de verdad, vía
  /// [aprobarMembresiaConductor] o [quitarRolConductorComoAdmin].
  /// Fire-and-forget en el llamador.
  Future<void> volverACliente(String uid) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'rol': 'cliente',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Auto-registro de un cliente como conductor (foto, vehículo, placa) desde
  /// `CompletarRegistroConductorView`. Distinto de `guardarConductor` (ese es
  /// el alta que hace un administrador con credenciales propias).
  Future<void> guardarSolicitudConductor({
    required String uid,
    required String foto,
    required String fotoVehiculo,
    required String placa,
    required String tipoVehiculo,
  }) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'foto': foto,
      'fotoVehiculo': fotoVehiculo,
      'placa': placa.toUpperCase(),
      'tipoVehiculo': tipoVehiculo,
      'rol': 'conductor',
      'solicitudConductor': true,
      'servicioActivo': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marca que el conductor pidió activar el servicio (paga membresía), desde
  /// `activacion_servicio_view`.
  Future<void> marcarSolicitudActivacion(String uid) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'solicitudConductor': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Desactiva la membresía al vencer el plazo (idempotente): usado por
  /// InicioConductorView cuando expira el timer de vencimiento.
  Future<void> expirarMembresia(String uid) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'membresia': '',
      'servicioActivo': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Aprueba la solicitud de activación de un conductor: activa su membresía
  /// por [dias] y le notifica por FCM si tiene token. Antes esta lógica (fecha
  /// de vencimiento + escritura Firestore + disparo FCM) vivía dentro de
  /// `_ConductorCard`, un `StatelessWidget` de `admin_home_screen.dart`.
  Future<void> aprobarMembresiaConductor({
    required String uid,
    required int dias,
    required String nombre,
    String? fcmToken,
  }) async {
    final inicio = DateTime.now();
    await _firestore.collection('usuarios').doc(uid).set({
      'membresia': 'activa',
      'membresiaDias': dias,
      'membresiaInicio': Timestamp.fromDate(inicio),
      'membresiaVence': Timestamp.fromDate(inicio.add(Duration(days: dias))),
      'servicioActivo': true,
      'solicitudConductor': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (fcmToken != null && fcmToken.isNotEmpty) {
      AdminFcmService.instance
          .sendToToken(
            token: fcmToken,
            title: '¡Membresía activada!',
            body:
                'Hola $nombre, tu membresía de conductor ya está activa por $dias días.',
            type: 'membresia_activada',
          )
          .ignore();
    }
  }

  /// Revoca la membresía activa de un conductor desde el panel de admin.
  /// Mismo efecto en datos que [expirarMembresia] (usado para el vencimiento
  /// automático); se expone con nombre propio para dejar clara la intención
  /// de cada llamador.
  Future<void> revocarMembresiaConductor(String uid) {
    return expirarMembresia(uid);
  }

  /// Quita el rol de conductor y resetea membresía/solicitud — acción de
  /// administrador. Distinto de [volverACliente] (autoservicio del propio
  /// conductor desde su perfil), que no limpia membresía/servicioActivo.
  Future<void> quitarRolConductorComoAdmin(String uid) async {
    await _firestore.collection('usuarios').doc(uid).set({
      'rol': 'cliente',
      'solicitudConductor': false,
      'membresia': '',
      'servicioActivo': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Elimina el registro de un usuario (cliente o conductor) desde el panel
  /// de administración. Antes esto era `doc.reference.delete()` directo desde
  /// `_ClienteCard`/`_ConductorCard` en `admin_home_screen.dart`.
  Future<void> eliminarUsuario(String uid) {
    return _firestore.collection('usuarios').doc(uid).delete();
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

  Future<bool> administradorRegistradoCompleto(String uid) async {
    final doc = await _firestore.collection('administradores').doc(uid).get();
    if (!doc.exists) return false;
    final data = doc.data() ?? <String, dynamic>{};
    final nombre = (data['nombre'] ?? '').toString().trim();
    final telefono = (data['telefono'] ?? '').toString().trim();
    final foto = (data['foto'] ?? '').toString().trim();
    final gremio = (data['gremio'] ?? '').toString().trim();
    return nombre.isNotEmpty &&
        telefono.isNotEmpty &&
        foto.isNotEmpty &&
        gremio.isNotEmpty;
  }

  Future<void> guardarAdministrador({
    required String uid,
    required String nombre,
    required String telefono,
    required String foto,
    required String gremio,
    String? correo,
  }) async {
    final data = <String, dynamic>{
      'uid': uid,
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'foto': foto,
      'gremio': gremio.trim(),
      'rol': 'administrador',
      'fechaRegistro': FieldValue.serverTimestamp(),
    };

    if (correo != null && correo.trim().isNotEmpty) {
      data['email'] = correo.trim().toLowerCase();
    }

    await _firestore
        .collection('administradores')
        .doc(uid)
        .set(data, SetOptions(merge: true));
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
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'user_data_service');
      }
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
    required String tipoVehiculo,
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
      'tipoVehiculo': tipoVehiculo,
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
        } catch (e, st) {
          developer.log(
            'No se pudo autenticar con credenciales anteriores del conductor: $e',
            name: 'UserDataService',
          );
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason:
                'UserDataService: fallo al re-autenticar con credenciales previas en actualizarCredencialesConductor',
          );
        }
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
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'user_data_service');
        }
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
      } catch (e, st) {
        developer.log(
          'No se pudo eliminar el documento de conductor anterior ($conductorId): $e',
          name: 'UserDataService',
        );
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason:
              'UserDataService: fallo al eliminar documento de conductor con id anterior tras cambio de correo',
        );
      }
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
