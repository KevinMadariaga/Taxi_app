import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BuscandoTaxiViewModel extends ChangeNotifier {
  BuscandoTaxiViewModel({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _solicitudSub;
  bool _disposed = false;
  bool _asignadaHandled = false;
  bool _isCancelling = false;
  String? _solicitudId;

  bool get isCancelling => _isCancelling;

  void iniciarEscucha({
    required String? solicitudId,
    required Future<void> Function(String solicitudId) onAsignada,
  }) {
    _solicitudId = solicitudId;
    _asignadaHandled = false;

    _solicitudSub?.cancel();
    if (solicitudId == null || solicitudId.isEmpty) return;

    _solicitudSub = _firestore
        .collection('solicitudes')
        .doc(solicitudId)
        .snapshots()
        .listen((snap) async {
          if (_asignadaHandled || !snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          final estado = (data['estado'] ?? data['status'])
              ?.toString()
              .toLowerCase();
          if (estado == 'asignado') {
            _asignadaHandled = true;
            try {
              await onAsignada(solicitudId);
            } catch (_) {
              _asignadaHandled = false;
            }
          }
        });
  }

  Future<void> detenerEscucha() async {
    final sub = _solicitudSub;
    _solicitudSub = null;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (_) {}
  }

  Future<void> cancelarSolicitud() async {
    if (_isCancelling) return;

    final solicitudId = _solicitudId;
    if (solicitudId == null || solicitudId.isEmpty) return;

    _isCancelling = true;
    _safeNotify();

    final docRef = _firestore.collection('solicitudes').doc(solicitudId);
    try {
      await docRef.update({
        'estado': 'cancelado',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      try {
        await docRef.delete();
      } catch (_) {}
    } finally {
      _isCancelling = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _solicitudSub?.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
