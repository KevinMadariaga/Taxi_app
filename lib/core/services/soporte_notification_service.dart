import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/utils/notificacion_clave.dart';

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
  StreamSubscription<QuerySnapshot>? _sugerenciasSub;
  DateTime? _userListenerStarted;
  DateTime? _adminListenerStarted;
  DateTime? _reportesListenerStarted;
  DateTime? _emergenciasListenerStarted;
  DateTime? _conductoresListenerStarted;
  DateTime? _sugerenciasListenerStarted;
  String? _currentUserId;

  /// Documentos ya notificados por cada listener, PERSISTIDOS.
  ///
  /// Los `_xxxListenerStarted` de arriba son campos de instancia: se reinician
  /// cada vez que se arranca la escucha, así que un admin que cerraba y volvía
  /// a abrir sesión recibía de nuevo las mismas emergencias, reportes y
  /// registros de conductor que ya había visto.
  ///
  /// La marca es por DOCUMENTO y no un timestamp por colección: con un solo
  /// `DateTime`, dos documentos nuevos en el mismo snapshot se pisaban (el
  /// primero en procesarse subía la marca y el segundo quedaba "viejo"), y
  /// `emergencias` ni siquiera tiene `orderBy`, así que dos emergencias
  /// simultáneas daban UNA sola notificación. Además un `timestamp` adelantado
  /// —campo que escribe el cliente— habría silenciado la colección entera para
  /// siempre en ese dispositivo.
  final Set<String> _yaVistos = {};
  static const String _prefsClave = 'soporte_docs_notificados';

  /// Cota para que la lista no crezca sin fin en un admin de sesión larga.
  static const int _maxVistos = 300;
  Future<void>? _cargaEnCurso;

  static const String claveAdmin = 'admin';
  static const String claveEmergencias = 'emergencias';
  static const String claveReportes = 'reportes';
  static const String claveConductores = 'conductores';
  static const String claveSugerencias = 'sugerencias';

  /// Carga los marcadores persistidos. Idempotente y seguro ante llamadas
  /// concurrentes: se guarda el Future, no una bandera puesta antes del
  /// `await` (con la bandera, la segunda llamada volvía enseguida con la
  /// lista todavía vacía y las escuchas arrancaban sin marcadores — el bug
  /// que esto venía a arreglar).
  Future<void> cargarUltimosVistos() => _cargaEnCurso ??= _cargar();

  Future<void> _cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _yaVistos.addAll(prefs.getStringList(_prefsClave) ?? const <String>[]);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
    }
  }

  /// `true` si ese documento ya se notificó. Si es nuevo, lo registra.
  bool _yaNotificado(String clave, String docId) {
    final marca = '$clave:$docId';
    if (!_yaVistos.add(marca)) return true;
    unawaited(_persistirVistos());
    return false;
  }

  Future<void> _persistirVistos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lista = _yaVistos.toList();
      if (lista.length > _maxVistos) {
        final sobrantes = lista.length - _maxVistos;
        _yaVistos.removeAll(lista.take(sobrantes));
        lista.removeRange(0, sobrantes);
      }
      await prefs.setStringList(_prefsClave, lista);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
    }
  }

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
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;

              final esAdmin = data['esAdmin'] as bool? ?? false;
              if (!esAdmin) continue;

              final ts = data['creadoEn'] as Timestamp?;
              final msgTime = ts?.toDate();
              final started = _userListenerStarted;
              if (msgTime != null &&
                  started != null &&
                  msgTime.isBefore(
                    started.subtract(const Duration(seconds: 2)),
                  )) {
                continue;
              }

              final texto =
                  data['texto'] as String? ?? 'Tienes un mensaje de soporte.';
              NotificacionesServicio.instance.showNotification(
                id: 900001,
                title: 'Soporte — Respuesta recibida',
                body: texto,
                payload: 'soporte_chat',
              );
            }
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
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
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added &&
                  change.type != DocumentChangeType.modified) {
                continue;
              }

              final data = change.doc.data();
              if (data == null) continue;

              final hayNuevos =
                  data['hayMensajesNuevosAdmin'] as bool? ?? false;
              if (!hayNuevos) continue;

              final ts = data['ultimoMensajeAt'] as Timestamp?;
              final msgTime = ts?.toDate();
              final started = _adminListenerStarted;
              if (msgTime != null &&
                  started != null &&
                  msgTime.isBefore(
                    started.subtract(const Duration(seconds: 2)),
                  )) {
                continue;
              }
              if (_yaNotificado(claveAdmin, change.doc.id)) continue;

              final userName = data['userName'] as String? ?? 'Usuario';
              final texto =
                  data['ultimoMensaje'] as String? ??
                  'Nuevo mensaje de soporte.';
              NotificacionesServicio.instance.showNotification(
                // Por usuario, no por nombre: `userName.hashCode` hacía que
                // todos los usuarios sin nombre compartieran una sola entrada.
                // El id del doc de `soporte_chats` es el uid, y así coincide
                // con la clave que usa el backend para el mismo aviso.
                id: idNotificacionDe('soporte_chat', change.doc.id),
                title: 'Soporte — $userName',
                body: texto,
                payload: 'admin_hub:1',
              );
            }
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
  }

  /// Escucha nuevas emergencias (botón de pánico) de los clientes.
  void iniciarEscuchaEmergencias() {
    _emergenciasSub?.cancel();
    _emergenciasListenerStarted = DateTime.now();

    _emergenciasSub = FirebaseFirestore.instance
        .collection('emergencias')
        .where('atendido', isEqualTo: false)
        .snapshots()
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
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
              if (_yaNotificado(claveEmergencias, change.doc.id)) continue;

              final motivos =
                  (data['motivos'] as List?)
                      ?.map((e) => e.toString())
                      .join(', ') ??
                  'Emergencia activada';
              NotificacionesServicio.instance.showNotification(
                id: change.doc.id.hashCode & 0x7fffffff,
                title: '🚨 EMERGENCIA — cliente en peligro',
                body: motivos.isNotEmpty
                    ? motivos
                    : 'Un cliente activó el botón de pánico.',
                channelId: 'taxi_emergencia_channel',
                channelName: 'Emergencias',
                payload: 'admin_hub:0',
              );
            }
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
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
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;

              final ts = data['createdAt'] as Timestamp?;
              final msgTime = ts?.toDate();
              final started = _reportesListenerStarted;
              if (msgTime != null &&
                  started != null &&
                  msgTime.isBefore(
                    started.subtract(const Duration(seconds: 2)),
                  )) {
                continue;
              }
              if (_yaNotificado(claveReportes, change.doc.id)) continue;

              final conductor = (data['conductor'] ?? 'conductor').toString();
              final motivos =
                  (data['motivos'] as List?)
                      ?.map((e) => e.toString())
                      .join(', ') ??
                  '';
              NotificacionesServicio.instance.showNotification(
                id: change.doc.id.hashCode & 0x7fffffff,
                title: 'Nuevo reporte — $conductor',
                body: motivos.isNotEmpty
                    ? motivos
                    : 'Reporte enviado por un cliente.',
                payload: 'admin_hub:0',
              );
            }
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
  }

  /// Escucha nuevas sugerencias de clientes y conductores.
  void iniciarEscuchaSugerencias() {
    _sugerenciasSub?.cancel();
    _sugerenciasListenerStarted = DateTime.now();

    _sugerenciasSub = FirebaseFirestore.instance
        .collection('sugerencias')
        .where('visto', isEqualTo: false)
        .snapshots()
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;

              final ts = data['creadoEn'] as Timestamp?;
              final msgTime = ts?.toDate();
              final started = _sugerenciasListenerStarted;
              if (msgTime != null &&
                  started != null &&
                  msgTime.isBefore(
                    started.subtract(const Duration(seconds: 2)),
                  )) {
                continue;
              }
              if (_yaNotificado(claveSugerencias, change.doc.id)) continue;

              final tipo = (data['tipo'] ?? 'usuario').toString();
              final mensaje = (data['mensaje'] ?? '').toString().trim();
              NotificacionesServicio.instance.showNotification(
                id: idNotificacionDe('sugerencia', change.doc.id),
                title: 'Nueva sugerencia — $tipo',
                body: mensaje.isNotEmpty
                    ? mensaje
                    : 'Un usuario envió una sugerencia.',
                payload: 'admin_hub:2',
              );
            }
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
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
        .listen(
          (snap) {
            for (final change in snap.docChanges) {
              // added = doc recién entró al query (solicitudConductor acaba de ser true).
              if (change.type != DocumentChangeType.added) continue;

              final data = change.doc.data();
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
              if (_yaNotificado(claveConductores, change.doc.id)) continue;

              // No notificar si ya tiene membresía activa.
              final membresia = (data['membresia'] ?? '')
                  .toString()
                  .toLowerCase();
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
          },
          onError: (Object e, StackTrace st) {
            ErrorReporter.report(e, st, reason: 'SoporteNotificationService');
          },
        );
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
    _sugerenciasSub?.cancel();
    _sugerenciasSub = null;
  }

  void detenerTodo() {
    detenerEscuchaUsuario();
    detenerEscuchaAdmin();
  }
}
