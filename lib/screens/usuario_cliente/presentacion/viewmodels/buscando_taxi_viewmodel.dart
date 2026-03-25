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
      // Primero intenta marcar como cancelado (si existe)
      await docRef.update({
        'estado': 'cancelado',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Si update falla, registramos y continuamos al intento de borrado posterior
      debugPrint('[BuscandoTaxiViewModel] update estado cancelado falló: $e');
    }

    // Espera 5 segundos y luego intenta eliminar la solicitud del sistema
    try {
      await Future<void>.delayed(const Duration(seconds: 5));
      try {
        await docRef.delete();
        debugPrint('[BuscandoTaxiViewModel] Solicitud $solicitudId eliminada tras cancelación');
      } catch (e) {
        debugPrint('[BuscandoTaxiViewModel] Error eliminando solicitud tras cancelación: $e');
      }
    } catch (e) {
      debugPrint('[BuscandoTaxiViewModel] Error en temporizador de borrado: $e');
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
