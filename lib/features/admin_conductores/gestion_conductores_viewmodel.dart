import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Conductor visto por el admin (doc de `usuarios` con rol/tipo conductor).
class ConductorAdminItem {
  ConductorAdminItem({
    required this.uid,
    required this.nombre,
    required this.telefono,
    required this.foto,
    required this.placa,
    required this.tipoVehiculo,
    required this.servicioHabilitado,
    required this.estadoSolicitud,
    required this.diasActivo,
    required this.servicioExpiraAt,
    required this.fechaSolicitud,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String foto;
  final String placa;
  final String tipoVehiculo;
  final bool servicioHabilitado;
  final String? estadoSolicitud;
  final int diasActivo;
  final DateTime? servicioExpiraAt;
  final DateTime? fechaSolicitud;

  bool get expirado =>
      servicioHabilitado &&
      servicioExpiraAt != null &&
      servicioExpiraAt!.isBefore(DateTime.now());

  /// Activo = habilitado y no expirado.
  bool get activo => servicioHabilitado && !expirado;

  /// Solicitud pendiente de activación (incluye expirados que piden reactivar).
  bool get pendiente => !servicioHabilitado || expirado;

  Duration? get tiempoRestante {
    final exp = servicioExpiraAt;
    if (!servicioHabilitado || exp == null) return null;
    final diff = exp.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  factory ConductorAdminItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    DateTime? toDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return ConductorAdminItem(
      uid: doc.id,
      nombre: (d['nombre'] ?? '').toString().trim(),
      telefono: (d['telefono'] ?? '').toString().trim(),
      foto: (d['foto'] ?? d['fotoUrl'] ?? '').toString().trim(),
      placa: (d['placa'] ?? '').toString().trim(),
      tipoVehiculo: (d['tipoVehiculo'] ?? '').toString().trim(),
      servicioHabilitado: d['servicioHabilitado'] == true,
      estadoSolicitud: d['estadoSolicitud']?.toString(),
      diasActivo: (d['diasActivo'] is num)
          ? (d['diasActivo'] as num).toInt()
          : 0,
      servicioExpiraAt: toDate(d['servicioExpiraAt']),
      fechaSolicitud:
          toDate(d['fechaSolicitudConductor']) ?? toDate(d['rolCambiadoAt']),
    );
  }
}

/// Gestiona los conductores desde el panel admin: lista, aprobación con días
/// activos (expiración) y rechazo.
class GestionConductoresViewModel extends ChangeNotifier {
  GestionConductoresViewModel({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  bool isLoading = true;
  String? errorMessage;
  List<ConductorAdminItem> _todos = [];

  List<ConductorAdminItem> get todos => List.unmodifiable(_todos);
  List<ConductorAdminItem> get pendientes =>
      _todos.where((c) => c.pendiente).toList();
  List<ConductorAdminItem> get activos =>
      _todos.where((c) => c.activo).toList();

  void iniciar() {
    _sub?.cancel();
    _sub = _firestore
        .collection('usuarios')
        .where('tipoUsuario', isEqualTo: 'conductor')
        .snapshots()
        .listen(
          (snap) {
            _todos = snap.docs.map(ConductorAdminItem.fromDoc).toList();
            _todos.sort((a, b) {
              // Pendientes primero, luego por fecha de solicitud desc.
              if (a.pendiente != b.pendiente) return a.pendiente ? -1 : 1;
              final am = a.fechaSolicitud?.millisecondsSinceEpoch ?? 0;
              final bm = b.fechaSolicitud?.millisecondsSinceEpoch ?? 0;
              return bm.compareTo(am);
            });
            isLoading = false;
            errorMessage = null;
            notifyListeners();
          },
          onError: (Object e) {
            isLoading = false;
            errorMessage = 'Error al cargar conductores: $e';
            notifyListeners();
          },
        );
  }

  /// Aprueba/activa el servicio del conductor por [dias] días.
  /// servicioExpiraAt = ahora + dias.
  Future<void> activarConductor(String uid, int dias) async {
    final ahora = DateTime.now();
    final expira = ahora.add(Duration(days: dias));
    final batch = _firestore.batch();
    final data = <String, dynamic>{
      'servicioHabilitado': true,
      'estadoSolicitud': 'aprobado',
      'diasActivo': dias,
      'servicioActivadoAt': Timestamp.fromDate(ahora),
      'servicioExpiraAt': Timestamp.fromDate(expira),
      'estado': 'activo',
    };
    batch.set(_firestore.collection('usuarios').doc(uid), data,
        SetOptions(merge: true));
    // Mantener colecciones espejo si existen.
    batch.set(_firestore.collection('conductor').doc(uid),
        {'servicioHabilitado': true, 'servicioExpiraAt': Timestamp.fromDate(expira), 'estado': 'activo'},
        SetOptions(merge: true));
    batch.set(_firestore.collection('conductores').doc(uid),
        {'servicioHabilitado': true, 'servicioExpiraAt': Timestamp.fromDate(expira), 'estado': 'activo'},
        SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> rechazarConductor(String uid) async {
    final batch = _firestore.batch();
    final data = <String, dynamic>{
      'servicioHabilitado': false,
      'estadoSolicitud': 'rechazado',
      'estado': 'inactivo',
    };
    batch.set(_firestore.collection('usuarios').doc(uid), data,
        SetOptions(merge: true));
    batch.set(_firestore.collection('conductor').doc(uid),
        {'servicioHabilitado': false, 'estado': 'inactivo'},
        SetOptions(merge: true));
    batch.set(_firestore.collection('conductores').doc(uid),
        {'servicioHabilitado': false, 'estado': 'inactivo'},
        SetOptions(merge: true));
    await batch.commit();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
