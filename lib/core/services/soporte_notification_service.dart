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
  StreamSubscription<QuerySnapshot>? _emergenciasSub;
  StreamSubscription<QuerySnapshot>? _conductoresSub;
  DateTime? _userListenerStarted;
  DateTime? _adminListenerStarted;
  DateTime? _reportesListenerStarted;
  DateTime? _emergenciasListenerStarted;
  DateTime? _conductoresListenerStarted;
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
        .where('hayMensajesNuevosAdmin', isEqualTo: true)
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

  /// Escucha nuevas emergencias (botón de pánico) de los clientes.
  void iniciarEscuchaEmergencias() {
    _emergenciasSub?.cancel();
    _emergenciasListenerStarted = DateTime.now();

    _emergenciasSub = FirebaseFirestore.instance
        .collection('emergencias')
        .where('atendido', isEqualTo: false)
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            final ts = data['timestamp'] as Timestamp?;
            final msgTime = ts?.toDate();
            final started = _emergenciasListenerStarted;
            if (msgTime != null &&
                started != null &&
                msgTime.isBefore(
                  started.subtract(const Duration(seconds: 2)),
                )) {
              continue;
            }

            final motivos = (data['motivos'] as List?)
                    ?.map((e) => e.toString())
                    .join(', ') ??
                'Emergencia activada';
            NotificacionesServicio.instance.showNotification(
              id: change.doc.id.hashCode & 0x7fffffff,
              title: '🚨 EMERGENCIA — cliente en peligro',
              body: motivos.isNotEmpty ? motivos : 'Un cliente activó el botón de pánico.',
              channelId: 'taxi_emergencia_channel',
              channelName: 'Emergencias',
              payload: 'admin_hub:3',
            );
          }
        }, onError: (_) {});
  }

  void detenerEscuchaEmergencias() {
    _emergenciasSub?.cancel();
    _emergenciasSub = null;
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

  /// Escucha nuevas solicitudes de registro de conductor.
  /// Notifica al admin cuando un conductor completa su registro y espera activación.
  void iniciarEscuchaConductores() {
    _conductoresSub?.cancel();
    _conductoresListenerStarted = DateTime.now();

    _conductoresSub = FirebaseFirestore.instance
        .collection('usuarios')
        .where('solicitudConductor', isEqualTo: true)
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            // added = doc recién entró al query (solicitudConductor acaba de ser true).
            if (change.type != DocumentChangeType.added) continue;

            final data = change.doc.data() as Map<String, dynamic>?;
            if (data == null) continue;

            // Ignorar docs que ya existían cuando arrancó el listener.
            final ts = data['updatedAt'] as Timestamp?;
            final msgTime = ts?.toDate();
            final started = _conductoresListenerStarted;
            if (msgTime != null &&
                started != null &&
                msgTime.isBefore(
                  started.subtract(const Duration(seconds: 2)),
                )) {
              continue;
            }

            // No notificar si ya tiene membresía activa.
            final membresia =
                (data['membresia'] ?? '').toString().toLowerCase();
            if (membresia == 'activa') continue;

            final nombre =
                (data['nombre'] ?? data['displayName'] ?? 'Un conductor')
                    .toString();
            NotificacionesServicio.instance.showNotification(
              id: change.doc.id.hashCode & 0x7fffffff,
              title: 'Nuevo conductor registrado',
              body: '$nombre quiere activar el servicio, revisa.',
              channelId: 'taxi_admin_channel',
              channelName: 'Notificaciones del Administrador',
              payload: 'admin_conductores',
            );
          }
        }, onError: (_) {});
  }

  void detenerEscuchaConductores() {
    _conductoresSub?.cancel();
    _conductoresSub = null;
  }

  void detenerEscuchaAdmin() {
    _adminSub?.cancel();
    _adminSub = null;
    _reportesSub?.cancel();
    _reportesSub = null;
    _emergenciasSub?.cancel();
    _emergenciasSub = null;
    _conductoresSub?.cancel();
    _conductoresSub = null;
  }

  void detenerTodo() {
    detenerEscuchaUsuario();
    detenerEscuchaAdmin();
  }
}
