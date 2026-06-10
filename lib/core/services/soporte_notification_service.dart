import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';

/// Escucha cambios en soporte_chats y muestra notificaciones locales.
/// Funciona mientras la app está en primer plano o en segundo plano activo.
class SoporteNotificationService {
  SoporteNotificationService._();
  static final SoporteNotificationService instance =
      SoporteNotificationService._();

  StreamSubscription<QuerySnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>? _adminSub;
  StreamSubscription<QuerySnapshot>? _reportesSub;
  DateTime? _userListenerStarted;
  DateTime? _adminListenerStarted;
  DateTime? _reportesListenerStarted;
  String? _currentUserId;

  /// Llama cuando el usuario (cliente o conductor) inicia sesión.
  /// Muestra notificación cuando el admin responde en el chat de soporte.
  void iniciarEscuchaUsuario(String userId) {
    if (_currentUserId == userId) return;
    _currentUserId = userId;
    _userSub?.cancel();
    _userListenerStarted = DateTime.now();

    _userSub = FirebaseFirestore.instance
        .collection('soporte_chats')
        .doc(userId)
        .collection('mensajes')
        .orderBy('creadoEn', descending: false)
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            final esAdmin = data['esAdmin'] as bool? ?? false;
            if (!esAdmin) continue;

            final ts = data['creadoEn'] as Timestamp?;
            final msgTime = ts?.toDate();
            final started = _userListenerStarted;
            if (msgTime != null && started != null &&
                msgTime.isBefore(started.subtract(const Duration(seconds: 2)))) {
              continue;
            }

            final texto = data['texto'] as String? ?? 'Tienes un mensaje de soporte.';
            NotificacionesServicio.instance.showNotification(
              id: 900001,
              title: 'Soporte — Respuesta recibida',
              body: texto,
              payload: 'soporte_chat',
            );
          }
        }, onError: (_) {});
  }

  /// Llama cuando el admin inicia sesión.
  /// Muestra notificación cuando un usuario envía un mensaje de soporte.
  void iniciarEscuchaAdmin() {
    _adminSub?.cancel();
    _adminListenerStarted = DateTime.now();

    _adminSub = FirebaseFirestore.instance
        .collection('soporte_chats')
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added &&
                change.type != DocumentChangeType.modified) continue;

            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            final hayNuevos =
                data['hayMensajesNuevosAdmin'] as bool? ?? false;
            if (!hayNuevos) continue;

            final ts = data['ultimoMensajeAt'] as Timestamp?;
            final msgTime = ts?.toDate();
            final started = _adminListenerStarted;
            if (msgTime != null && started != null &&
                msgTime.isBefore(started.subtract(const Duration(seconds: 2)))) {
              continue;
            }

            final userName = data['userName'] as String? ?? 'Usuario';
            final texto =
                data['ultimoMensaje'] as String? ?? 'Nuevo mensaje de soporte.';
            NotificacionesServicio.instance.showNotification(
              id: userName.hashCode & 0x7fffffff,
              title: 'Soporte — $userName',
              body: texto,
              payload: 'admin_hub:2',
            );
          }
        }, onError: (_) {});
  }

  void detenerEscuchaUsuario() {
    _userSub?.cancel();
    _userSub = null;
    _currentUserId = null;
  }

  /// Escucha nuevos reportes de conductores enviados por clientes.
  void iniciarEscuchaReportes() {
    _reportesSub?.cancel();
    _reportesListenerStarted = DateTime.now();

    _reportesSub = FirebaseFirestore.instance
        .collection('reportes')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            final ts = data['createdAt'] as Timestamp?;
            final msgTime = ts?.toDate();
            final started = _reportesListenerStarted;
            if (msgTime != null && started != null &&
                msgTime.isBefore(started.subtract(const Duration(seconds: 2)))) {
              continue;
            }

            final conductor = (data['conductor'] ?? 'conductor').toString();
            final motivos = (data['motivos'] as List?)
                    ?.map((e) => e.toString())
                    .join(', ') ??
                '';
            NotificacionesServicio.instance.showNotification(
              id: change.doc.id.hashCode & 0x7fffffff,
              title: 'Nuevo reporte — $conductor',
              body: motivos.isNotEmpty ? motivos : 'Reporte enviado por un cliente.',
              payload: 'admin_hub:1',
            );
          }
        }, onError: (_) {});
  }

  void detenerEscuchaAdmin() {
    _adminSub?.cancel();
    _adminSub = null;
    _reportesSub?.cancel();
    _reportesSub = null;
  }

  void detenerTodo() {
    detenerEscuchaUsuario();
    detenerEscuchaAdmin();
  }
}
