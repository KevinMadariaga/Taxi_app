import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/complete_profile_page.dart';
import 'package:taxi_app/features/admin/admin_home_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/vistas/viaje_cliente_screen.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/vistas/viaje_conductor_screen.dart';

import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Resuelve la pantalla inicial de la app según el estado de autenticación
/// y las solicitudes activas del usuario.
///
/// Extraído de `AuthService`, que mezclaba sesión/login puro con esta
/// lógica de navegación. Depende de `AuthService` solo para lo que sigue
/// siendo responsabilidad de sesión/auth (p. ej. limpieza de sesión
/// persistida compartida con `logout`/`clearSession`).
class InitialScreenResolver {
  InitialScreenResolver({AuthService? authService})
    : _authService = authService ?? AuthService();

  final AuthService _authService;

  bool _activeSolicitudNotificationShown = false;

  /// Determina si, para un conductor, la solicitud ya está en curso hacia el
  /// destino (`RutaDestino`) en vez de camino al cliente (`DriverTripScreen`).
  ///
  /// `estado` debe venir ya normalizado con [SolicitudEstado.normalize] —
  /// antes esto se evaluaba con `.contains()` sobre substrings sin espacio
  /// ('enruta', 'encam') que nunca matcheaban el valor canónico ('en ruta',
  /// 'en camino'), así que solo se activaba por accidente vía 'camino'.
  static bool conductorInProgressForEstado(String estado) {
    return estado == SolicitudEstado.enRuta;
  }

  /// Determina la pantalla inicial según el estado de autenticación
  /// y las solicitudes activas del usuario
  Future<Widget> determineInitialScreen() async {
    try {
      // Obtener SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Verificar solicitudes activas en SharedPreferences legacy, RouteCache y en SessionHelper
      final solicitudActivaCliente = _getSolicitudActivaCliente(prefs);
      final solicitudActivaConductor = _getSolicitudActivaConductor(prefs);
      final activeFromSession = await SessionHelper.getActiveSolicitud();
      final activeFromRouteCache =
          await RouteCacheService.getActiveSolicitudId();

      // Verificar autenticación
      final currentUser = FirebaseAuth.instance.currentUser;
      final isLogged = prefs.getBool('is_logged_in') ?? false;
      // Rol cacheado del último login (guardado por AuthService.saveUserSession).
      // Solo se usa para: (a) detectar residuos de sesión cuando ya no hay
      // usuario de Firebase, y (b) como fallback si Firestore no es alcanzable
      // más abajo. NUNCA es la fuente de verdad del rol de un usuario
      // autenticado — ese siempre se re-deriva de Firestore (ver bloque
      // `if (currentUser != null)`), porque el rol pudo cambiar server-side
      // (promoción/democión de admin, alta como conductor, etc.) desde el
      // último login, y confiar en el caché podía rutear a un usuario a un
      // panel/rol que ya no le corresponde.
      final cachedRole = prefs.getString('user_role');
      String? role = cachedRole;
      final persistedUid = prefs.getString('user_uid');

      // Si no hay usuario Firebase pero hay residuos locales de sesión,
      // limpiar todo para evitar restauraciones incorrectas tras logout/reload.
      final hasLocalAuthResidue =
          isLogged ||
          (role != null && role.isNotEmpty) ||
          (persistedUid != null && persistedUid.isNotEmpty) ||
          (activeFromSession != null && activeFromSession.isNotEmpty) ||
          (activeFromRouteCache != null && activeFromRouteCache.isNotEmpty) ||
          (solicitudActivaCliente != null &&
              solicitudActivaCliente.isNotEmpty) ||
          (solicitudActivaConductor != null &&
              solicitudActivaConductor.isNotEmpty);
      if (currentUser == null && hasLocalAuthResidue) {
        await _authService.clearPersistedSessionAndCaches(prefs);
        try {
          await SessionHelper.clearSession();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'auth_service');
        }
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'auth_service');
        }
        return const HomeView();
      }

      // Si hay un usuario autenticado, el rol SIEMPRE se re-deriva de
      // Firestore desde cero (nunca se parte del cacheado) — ver comentario
      // de `cachedRole` arriba.
      if (currentUser != null) {
        role = null;
        try {
          final uid = currentUser.uid;
          final adminDoc = await FirebaseFirestore.instance
              .collection('administradores')
              .doc(uid)
              .get();

          if (adminDoc.exists) {
            role = 'administrador';
          }

          final usuariosDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get();

          final userData = usuariosDoc.data() ?? <String, dynamic>{};
          // `isProfileComplete` se evalúa UNA sola vez y fuera de las ramas de
          // rol. Antes vivía anidado dentro de `usuariosDoc.exists && rol ==
          // 'cliente'`, así que el gate se saltaba por completo cuando el doc
          // no existía o cuando el rol venía por el fallback `tipoUsuario`.
          final perfilCompletoEnDoc = userData['isProfileComplete'] == true;

          if (usuariosDoc.exists && role != 'administrador') {
            final userRole = (userData['rol'] ?? userData['role'] ?? '')
                .toString()
                .toLowerCase();

            if (userRole == 'admin' || userRole == 'administrador') {
              role = 'administrador';
            } else if (userRole == 'conductor') {
              role = 'conductor';
            } else if (userRole == 'cliente') {
              role = 'cliente';
            }
          }

          // Si usuarios.rol/role no resolvió, usar tipoUsuario como fallback
          // (campo alterno que sí usa, por ejemplo, el alta de conductor).
          if (role != 'administrador' &&
              role != 'conductor' &&
              role != 'cliente') {
            final tipoUsuario = (userData['tipoUsuario'] ?? '')
                .toString()
                .toLowerCase();
            if (tipoUsuario == 'conductor') {
              role = 'conductor';
            } else if (tipoUsuario == 'cliente') {
              role = 'cliente';
            }
          }

          // Ni admin, ni usuarios.rol/role, ni tipoUsuario resolvieron nada
          // reconocible (doc inexistente, campo vacío, valor inesperado):
          // default explícito a 'cliente' (el de menor privilegio) en vez de
          // dejar `role` en null — null ahí terminaría reusando el rol
          // cacheado más abajo en el resto de la función, que es justo lo
          // que este bloque existe para evitar.
          role ??= 'cliente';

          // Un cliente autenticado SIN documento legible en `usuarios` tiene,
          // por definición, el perfil incompleto: es el estado que queda si
          // `ensureClientUserForGoogle` falló después de un sign-in exitoso.
          // Tratarlo como completo lo dejaba entrar al home sin nombre, sin
          // teléfono y sin foto.
          final perfilCompleto = usuariosDoc.exists && perfilCompletoEnDoc;

          // Firestore fue alcanzable y dio un rol confiable: sincronizar el
          // caché para que, si alguna vez Firestore no es alcanzable (ver
          // catch abajo), el fallback offline sea el último rol REAL
          // conocido, no uno arbitrariamente viejo.
          if (role != cachedRole) {
            try {
              await prefs.setString('user_role', role);
            } catch (e, st) {
              ErrorReporter.report(e, st, reason: 'auth_service');
            }
          }
          // Se cachea también si el perfil está completo, para poder aplicar
          // el mismo criterio cuando Firestore no responda (ver catch).
          try {
            await prefs.setBool('profile_complete', perfilCompleto);
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'auth_service');
          }

          if (role == 'cliente' && !perfilCompleto) {
            return CompleteProfilePage(
              uid: uid,
              initialNombre: (userData['nombre'] ?? '').toString(),
              initialApellido: (userData['apellido'] ?? '').toString(),
              initialTelefono: (userData['telefono'] ?? '').toString(),
            );
          }
        } catch (e, st) {
          debugPrint('Error al resolver rol de usuario desde Firestore: $e');
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason:
                'AuthService: fallo al resolver rol de usuario desde Firestore',
          );
          // Sin conectividad (u otro fallo) para confirmar el rol real: usar
          // el último rol cacheado como fallback degradado, mejor que dejar
          // a un usuario ya autenticado varado en el login. No es el camino
          // feliz — el rol real se re-confirma en el siguiente cold start
          // con red disponible.
          role = cachedRole;

          // El gate de perfil también se resuelve con el caché: antes este
          // catch lo salteaba por completo, así que un perfil incompleto
          // entraba al home cada vez que se arrancara sin red. Si nunca se
          // confirmó que estuviera completo, se asume incompleto.
          if (role == 'cliente' && prefs.getBool('profile_complete') != true) {
            return CompleteProfilePage(uid: currentUser.uid);
          }
        }
      }

      // Determinar id de solicitud candidata (SessionHelper tiene prioridad)
      String? candidateSolicitudId;
      if (activeFromSession != null && activeFromSession.isNotEmpty) {
        candidateSolicitudId = activeFromSession;
      } else if (activeFromRouteCache != null &&
          activeFromRouteCache.isNotEmpty) {
        candidateSolicitudId = activeFromRouteCache;
      } else if (role == 'administrador') {
        candidateSolicitudId = null;
      } else if (role == 'conductor') {
        candidateSolicitudId = solicitudActivaConductor;
      } else {
        candidateSolicitudId = solicitudActivaCliente;
      }

      // Prepare current uid early so saved-screen restore can include it.
      final currentUid = currentUser?.uid;

      // --- PATCH: Forzar restauración correcta para clientes ---
      // Respect the explicit saved screen for an active solicitud (if any),
      // pero SOLO si la solicitud sigue viva en Firestore. Este flag de
      // SharedPreferences puede quedar obsoleto (viaje anterior completado,
      // o solicitud nueva que quedó en 'buscando' y nunca se canceló porque
      // el proceso fue matado desde recientes antes de que corriera el timer
      // de inactividad del cliente) — confiar en él a ciegas reenganchaba a
      // pantallas de viaje (ruta_cliente_destino, etc.) para solicitudes ya
      // terminadas o abandonadas. Si no es restaurable, se limpia el flag y
      // se cae al flujo normal de abajo, que sí valida el estado real y
      // cancela por inactividad si corresponde.
      final savedActiveScreen = await SessionHelper.getActiveSolicitudScreen();
      if (savedActiveScreen != null &&
          savedActiveScreen.isNotEmpty &&
          candidateSolicitudId != null &&
          candidateSolicitudId.isNotEmpty) {
        if (await _isSolicitudRestaurable(candidateSolicitudId)) {
          // If the user had a specific view open (client or driver), restore
          // it. 'trip_tracking'/'ruta_cliente_destino': valores legacy de
          // antes de unificar el cliente en una sola pantalla — se
          // mantienen como fallback por si quedó un flag guardado de una
          // versión anterior.
          if (savedActiveScreen == 'viaje_cliente' ||
              savedActiveScreen == 'trip_tracking' ||
              savedActiveScreen == 'ruta_cliente_destino') {
            return ViajeClienteScreen(
              viajeId: candidateSolicitudId,
              currentUserId: currentUid ?? '',
            );
          }
          // 'driver_trip'/'ruta_destino': valores legacy de antes de
          // unificar el conductor en una sola pantalla — se mantienen como
          // fallback por si quedó un flag guardado de una versión anterior.
          if (savedActiveScreen == 'viaje_conductor' ||
              savedActiveScreen == 'driver_trip' ||
              savedActiveScreen == 'ruta_destino') {
            return ViajeConductorScreen(viajeId: candidateSolicitudId);
          }
        } else {
          try {
            await SessionHelper.clearActiveSolicitudScreen();
          } catch (e, st) {
            ErrorReporter.report(e, st, reason: 'auth_service');
          }
        }
      }

      // Si el usuario es cliente y está autenticado, siempre restaurar InicioClienteView
      if (currentUser != null && (role == 'cliente' || role == null)) {
        // Si hay una solicitud activa, seguir el flujo normal
        if (candidateSolicitudId != null && candidateSolicitudId.isNotEmpty) {
          final screen = await _buildScreenForActiveSolicitud(
            solicitudId: candidateSolicitudId,
            role: 'cliente',
          );
          if (screen != null) {
            return screen;
          }
        }
        // Si no hay solicitud activa, ir siempre a InicioClienteView
        return const HomeClienteView();
      }

      // Si el usuario está autenticado
      if (currentUser != null) {
        // 1) Usuario identificado: primero validar estado de una solicitud activa
        if (candidateSolicitudId != null && candidateSolicitudId.isNotEmpty) {
          final screen = await _buildScreenForActiveSolicitud(
            solicitudId: candidateSolicitudId,
            role: role,
          );
          if (screen != null) {
            return screen;
          }
        }

        // 1.1) Fallback: rehidratar solicitud activa desde Firestore si no hay cache local
        if (currentUid != null && currentUid.isNotEmpty) {
          final fromFirestore = await _findActiveSolicitudIdForUser(
            uid: currentUid,
            role: role,
          );
          if (fromFirestore != null && fromFirestore.isNotEmpty) {
            try {
              await SessionHelper.setActiveSolicitud(fromFirestore);
            } catch (e, st) {
              ErrorReporter.report(e, st, reason: 'auth_service');
            }

            final screen = await _buildScreenForActiveSolicitud(
              solicitudId: fromFirestore,
              role: role,
            );
            if (screen != null) {
              return screen;
            }
          }
        }

        // 2) Si no hay solicitud activa válida, ir a la pantalla principal según rol
        return _getAuthenticatedUserScreen(role: role, uid: currentUid);
      }

      // Por defecto, ir a login
      return const HomeView();
    } catch (e) {
      debugPrint('Error al determinar pantalla inicial: $e');
      return const HomeView();
    }
  }

  /// Obtiene la solicitud activa del cliente desde SharedPreferences
  String? _getSolicitudActivaCliente(SharedPreferences prefs) {
    // Prefer explicit saved key
    final explicit = prefs.getString('cliente_solicitud_activa');
    if (explicit != null && explicit.isNotEmpty) return explicit;

    // Fallback: buscar por claves de progreso antiguas
    for (String key in prefs.getKeys()) {
      if (key.startsWith('solicitud_progreso_')) {
        return key.replaceFirst('solicitud_progreso_', '');
      }
    }
    return null;
  }

  /// Obtiene la solicitud activa del conductor desde SharedPreferences
  String? _getSolicitudActivaConductor(SharedPreferences prefs) {
    return prefs.getString('conductor_solicitud_activa');
  }

  /// Retorna la pantalla correspondiente para un usuario autenticado
  Widget _getAuthenticatedUserScreen({required String? role, String? uid}) {
    if (role == 'administrador') {
      final adminId = (uid ?? '').trim();
      if (adminId.isNotEmpty) {
        return AdminHomeScreen(adminId: adminId);
      }
      return const HomeView();
    }

    if (role == 'conductor') {
      // Usuario conductor sin solicitud activa
      return const InicioConductor();
    } else {
      // Usuario cliente (rol == 'cliente' o null) sin solicitud activa
      return const HomeClienteView();
    }
  }

  /// Verifica en Firestore si `solicitudId` sigue en un estado que amerite
  /// restaurar la pantalla de viaje guardada (`active_solicitud_screen`).
  /// Devuelve `false` para solicitudes terminadas (completada/cancelada/
  /// finalizada) o huérfanas en `'buscando'` (app matada antes de que un
  /// conductor la tomara), que es exactamente el estado en el que queda una
  /// solicitud si el proceso se mató desde recientes y el timer de
  /// inactividad del cliente no llegó a correr.
  Future<bool> _isSolicitudRestaurable(String solicitudId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();
      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final estado = SolicitudEstado.normalize(
        (data['status'] ?? data['estado'] ?? '').toString(),
      );

      if (SolicitudEstado.isTerminal(estado)) {
        return false;
      }

      return estado != SolicitudEstado.buscando;
    } catch (_) {
      // Si no se puede verificar (sin red, etc.), preferir no bloquear la
      // restauración antes que dejar al usuario varado sin contexto.
      return true;
    }
  }

  /// Construye la pantalla de ruta correspondiente si la solicitud está activa y asignada
  Future<Widget?> _buildScreenForActiveSolicitud({
    required String solicitudId,
    required String? role,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('solicitudes')
          .doc(solicitudId)
          .get();

      if (!doc.exists) {
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'auth_service');
        }
        return null;
      }

      final data = doc.data();
      if (data == null) return null;

      final estado = SolicitudEstado.normalize(
        (data['status'] ?? data['estado'] ?? '').toString(),
      );

      // No restaurar si está completada, cancelada o sin respuesta (terminal).
      // Antes esto solo miraba complet/cancel/finaliz y se saltaba 'sin
      // respuesta', dejando que una solicitud ya cerrada por timeout se
      // tratara como activa/restaurable más abajo.
      if (SolicitudEstado.isTerminal(estado)) {
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'auth_service');
        }
        return null;
      }

      // Si la solicitud quedó en 'buscando' (app fue cerrada/matada antes de
      // que llegara un conductor), cancelarla automáticamente al reabrir y
      // borrarla a los 3 s (igual que una cancelación normal), para que
      // desaparezca de la lista de solicitudes de los conductores.
      if (estado == SolicitudEstado.buscando) {
        final docRef = FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(solicitudId);
        try {
          await docRef.update({
            'estado': SolicitudEstado.cancelado,
            'cancelledAt': FieldValue.serverTimestamp(),
            'cancelReason': 'inactividad',
          });
          unawaited(
            Future<void>.delayed(const Duration(seconds: 3), () async {
              try {
                await docRef.delete();
              } catch (e, st) {
                ErrorReporter.report(e, st, reason: 'auth_service');
              }
            }),
          );
        } catch (e, st) {
          debugPrint('Error al cancelar solicitud huérfana en buscando: $e');
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason:
                'AuthService: fallo al auto-cancelar solicitud huérfana en estado buscando',
          );
        }
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (e, st) {
          ErrorReporter.report(e, st, reason: 'auth_service');
        }
        return null;
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      // Resolver ids de conductor y cliente desde el documento
      String? conductorId;
      final rawConductor = data['conductor'];
      if (rawConductor is Map) {
        conductorId =
            (rawConductor['id'] ??
                    rawConductor['uid'] ??
                    rawConductor['conductorId'] ??
                    rawConductor['driverId'])
                ?.toString();
      } else {
        conductorId =
            (data['conductorId'] ??
                    data['conductor_id'] ??
                    data['assignedTo'] ??
                    data['driverId'])
                ?.toString();
      }

      String? clienteId;
      final rawCliente = data['cliente'];
      if (rawCliente is Map) {
        clienteId =
            (rawCliente['id'] ?? rawCliente['uid'] ?? rawCliente['clienteId'])
                ?.toString();
      } else {
        clienteId = (data['clienteId'] ?? data['userId'] ?? data['cliente_id'])
            ?.toString();
      }

      final isCurrentDriver =
          conductorId != null &&
          currentUid != null &&
          currentUid == conductorId;
      final isCurrentClient =
          clienteId != null && currentUid != null && currentUid == clienteId;

      // Conductor: rol explícito o coincide con el asignado. Antes esto
      // elegía entre `DriverTripScreen` (camino al cliente) y `RutaDestino`
      // (camino al destino) según `conductorInProgressForEstado` — con
      // `ViajeConductorScreen` unificado ya no hay dos pantallas entre las
      // que elegir, el propio viewmodel reacciona al estado en vivo.
      if (role == 'conductor' || isCurrentDriver) {
        return ViajeConductorScreen(viajeId: solicitudId);
      }

      // Cliente: rol explícito, rol desconocido o coincide con el cliente.
      // Antes elegía entre `TripTrackingScreen`/`RutaClienteDestino` según
      // la caché de ruta — con `ViajeClienteScreen` unificado ya no hay dos
      // pantallas entre las que elegir.
      if (role == 'cliente' || role == null || isCurrentClient) {
        final estadoNormalizado = SolicitudEstado.normalize(estado);
        if (SolicitudEstado.isSesionActiva(estadoNormalizado)) {
          await _notifyActiveSolicitudOnAppOpen();
        }

        return ViajeClienteScreen(
          viajeId: solicitudId,
          currentUserId: currentUid ?? clienteId ?? '',
        );
      }
    } catch (e, st) {
      debugPrint('Error al construir pantalla para solicitud activa: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'AuthService: fallo al construir pantalla para solicitud activa',
      );
    }

    return null;
  }

  Future<String?> _findActiveSolicitudIdForUser({
    required String uid,
    required String? role,
  }) async {
    // Solo los dos campos que el esquema escribe de verdad
    // (`solicitud_repository_impl.crear` escribe `cliente.id`;
    // `InicioConductorViewModel._buildConductorPayload` escribe
    // `conductor.id`; ver `test/esquema_solicitud_contrato_test.dart`).
    //
    // Antes se probaban 6 variantes por rol (`conductor.uid`, `conductorId`,
    // `conductor_id`, `assignedTo`, `driverId`, `cliente.uid`, `clienteId`,
    // `cliente_id`, `userId`). Ninguna la escribe este código, y desde que
    // las reglas de Firestore están cerradas **no pueden funcionar nunca**:
    // la regla de `solicitudes` solo puede demostrar que una query es legible
    // si filtra por `cliente.id` o `conductor.id`, así que las demás se
    // rechazan enteras sin importar los datos. Cada arranque sin viaje activo
    // gastaba 5 queries fallidas en serie —latencia en el splash— y mandaba
    // 5 errores a Crashlytics por usuario, enterrando los crashes reales.
    final queries = <String>[];

    if (role == 'conductor') {
      queries.add('conductor.id');
    } else {
      queries.add('cliente.id');
    }

    // Si el rol es ambiguo, intentamos ambos lados para maximizar restauracion.
    if (role == null) {
      queries.add('conductor.id');
    }

    for (final field in queries.toSet()) {
      final found = await _findActiveSolicitudByField(field: field, uid: uid);
      if (found != null && found.isNotEmpty) {
        return found;
      }
    }

    return null;
  }

  Future<String?> _findActiveSolicitudByField({
    required String field,
    required String uid,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('solicitudes')
          .where(field, isEqualTo: uid)
          .limit(20)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final estado = SolicitudEstado.normalize(
          (data['status'] ?? data['estado'] ?? '').toString(),
        );

        if (SolicitudEstado.isTerminal(estado)) {
          continue;
        }

        return doc.id;
      }
    } catch (e, st) {
      debugPrint('Error al buscar solicitud activa por campo "$field": $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'AuthService: fallo al buscar solicitud activa por campo "$field"',
      );
    }

    return null;
  }

  Future<void> _notifyActiveSolicitudOnAppOpen() async {
    if (_activeSolicitudNotificationShown) return;
    _activeSolicitudNotificationShown = true;

    try {
      await NotificacionesServicio.instance.init();
      await NotificacionesServicio.instance.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: 'Solicitud activa',
        body: 'Tienes una solicitud activa en curso.',
      );
    } catch (e, st) {
      debugPrint('Error al notificar solicitud activa al abrir la app: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason:
            'AuthService: fallo al mostrar notificación de solicitud activa al abrir la app',
      );
    }
  }
}
