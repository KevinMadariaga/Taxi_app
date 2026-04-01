import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/features/trip_tracking_cliente/views/trip_tracking_screen.dart';
import 'package:taxi_app/presentation/screens/auth/complete_profile_page.dart';
import 'package:taxi_app/features/phone_auth/screens/panel_administrador_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/RutaClienteDestinoView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/RutaDestinoView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/features/driver_trip/screens/driver_trip_screen.dart';

import 'package:taxi_app/core/services/services.dart';

/// Servicio que maneja la verificación de sesión y redirección
/// a la pantalla correspondiente según el estado del usuario
class AuthService {
  AuthService();

  bool _activeSolicitudNotificationShown = false;

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
      String? role = prefs.getString('user_role');
      final persistedUid = prefs.getString('user_uid');

      // Si no hay usuario Firebase pero hay residuos locales de sesión,
      // limpiar todo para evitar restauraciones incorrectas tras logout/reload.
      final hasLocalAuthResidue =
          isLogged ||
          (role != null && role.isNotEmpty) ||
          (persistedUid != null && persistedUid.isNotEmpty) ||
          (activeFromSession != null && activeFromSession.isNotEmpty) ||
          (activeFromRouteCache != null && activeFromRouteCache.isNotEmpty) ||
          (solicitudActivaCliente != null && solicitudActivaCliente.isNotEmpty) ||
          (solicitudActivaConductor != null && solicitudActivaConductor.isNotEmpty);
      if (currentUser == null && hasLocalAuthResidue) {
        await _clearPersistedSessionAndCaches(prefs);
        try {
          await SessionHelper.clearSession();
        } catch (_) {}
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (_) {}
        return const HomeView();
      }

      // Si hay un usuario autenticado, intentar detectar su rol basado en Firestore
      if (currentUser != null) {
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

          if (usuariosDoc.exists && role != 'administrador') {
            final userData = usuariosDoc.data() ?? <String, dynamic>{};
            final userRole = (userData['rol'] ?? '').toString().toLowerCase();
            final isProfileComplete = userData['isProfileComplete'] == true;

            if (userRole == 'cliente') {
              role = 'cliente';

              if (!isProfileComplete) {
                return CompleteProfilePage(
                  uid: uid,
                  initialNombre: (userData['nombre'] ?? '').toString(),
                  initialApellido: (userData['apellido'] ?? '').toString(),
                  initialTelefono: (userData['telefono'] ?? '').toString(),
                );
              }
            }
          }

          if (role != 'administrador') {
            final conductorDoc = await FirebaseFirestore.instance
                .collection('conductor')
                .doc(uid)
                .get();
            if (conductorDoc.exists) {
              role = 'conductor';
            } else {
              final clienteDoc = await FirebaseFirestore.instance
                  .collection('cliente')
                  .doc(uid)
                  .get();
              if (clienteDoc.exists) role = 'cliente';
            }
          }
        } catch (_) {}
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
      // Respect the explicit saved screen for an active solicitud (if any).
      final savedActiveScreen = await SessionHelper.getActiveSolicitudScreen();
      if (savedActiveScreen != null && savedActiveScreen.isNotEmpty && candidateSolicitudId != null && candidateSolicitudId.isNotEmpty) {
        // If the user had a specific view open (client or driver), restore it.
        if (savedActiveScreen == 'trip_tracking') {
          return TripTrackingScreen(
            solicitudId: candidateSolicitudId,
            currentUserId: currentUid ?? '',
            cancelledBy: 'cliente',
          );
        }
        if (savedActiveScreen == 'ruta_cliente_destino') {
          return RutaClienteDestino(idSolicitud: candidateSolicitudId);
        }
        if (savedActiveScreen == 'driver_trip') {
          return DriverTripScreen(tripId: candidateSolicitudId);
        }
        if (savedActiveScreen == 'ruta_destino') {
          return RutaDestino(idSolicitud: candidateSolicitudId);
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
            } catch (_) {}

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
        return PanelAdministradorScreen(adminId: adminId);
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
        } catch (_) {}
        return null;
      }

      final data = doc.data();
      if (data == null) return null;

      final estado = (data['status'] ?? data['estado'] ?? '')
          .toString()
          .toLowerCase();

      // No restaurar si está completada o cancelada
      if (estado.contains('complet') ||
          estado.contains('cancel') ||
          estado.contains('finaliz')) {
        try {
          await SessionHelper.clearActiveSolicitud();
        } catch (_) {}
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

      // Conductor: rol explícito o coincide con el asignado
      if (role == 'conductor' || isCurrentDriver) {
        final conductorInProgress =
            estado.contains('progr') ||
            estado.contains('en_progr') ||
            estado.contains('enruta') ||
            estado.contains('viaj') ||
            estado.contains('camino') ||
            estado.contains('encam');

        // if (conductorInProgress) {
        //   return TripRouteTrackingScreen(
        //     solicitudId: solicitudId,
        //     currentUserId: currentUid ?? conductorId ?? '',
        //     tipoUsuario: TipoUsuarioTracking.conductor,
        //   );
        // }
        // Try to restore cached route data to preserve UI state after reload (non in-progress)
        try {
          final cache = await RouteCacheService.loadForSolicitud(solicitudId);
          if (cache != null) {
            // If the cached role is 'conductor' and the trip is already in-progress,
            // restore the in-route UI (`RutaDestino`). Otherwise, restore the
            // driver trip UI (`RutaConductor`) which maps to `DriverTripScreen`.
            if (cache.role == 'conductor') {
              if (conductorInProgress) {
                return RutaDestino(idSolicitud: solicitudId);
              }
              return RutaConductor(idSolicitud: solicitudId);
            }
            // Fallback: return the legacy conductor wrapper
            return RutaConductor(idSolicitud: solicitudId);
          }
        } catch (_) {}

        return RutaConductor(idSolicitud: solicitudId);
      }

      // Cliente: rol explícito, rol desconocido o coincide con el cliente
      if (role == 'cliente' || role == null || isCurrentClient) {
        final estadoNormalizado = _normalizeEstadoCliente(estado);
        if (_isSolicitudActivaCliente(estadoNormalizado)) {
          await _notifyActiveSolicitudOnAppOpen();
        }

        // If we have cached route UI for this solicitud (cliente), restore RutaClienteDestino
        try {
          final cache = await RouteCacheService.loadForSolicitud(solicitudId);
          if (cache != null && cache.role == 'cliente') {
            return RutaClienteDestino(idSolicitud: solicitudId);
          }
        } catch (_) {}

        // Fallback: default tracking screen
        return TripTrackingScreen(
          solicitudId: solicitudId,
          currentUserId: currentUid ?? clienteId ?? '',
          cancelledBy: 'cliente',
        );
      }
    } catch (_) {}

    return null;
  }

  /// Verifica si el usuario está autenticado
  Future<bool> isUserAuthenticated() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final prefs = await SharedPreferences.getInstance();
      final isLogged = prefs.getBool('is_logged_in') ?? false;

      return currentUser != null || isLogged;
    } catch (e) {
      debugPrint('Error al verificar autenticación: $e');
      return false;
    }
  }

  /// Obtiene el rol del usuario actual
  Future<String?> getUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_role');
    } catch (e) {
      debugPrint('Error al obtener rol de usuario: $e');
      return null;
    }
  }

  /// Limpia la sesión del usuario
  Future<void> clearSession() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await _clearPersistedSessionAndCaches(prefs);
    } catch (e) {
      debugPrint('Error al limpiar sesión: $e');
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error al cerrar sesión en FirebaseAuth: $e');
    }

    if (prefs != null) {
      try {
        await _clearPersistedSessionAndCaches(prefs);
      } catch (_) {}
    }
  }

  /// Guarda la información de sesión del usuario
  Future<void> saveUserSession({
    required String role,
    required bool isLoggedIn,
    String? uid,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', isLoggedIn);
      await prefs.setString('user_role', role);

      final resolvedUid = (uid ?? FirebaseAuth.instance.currentUser?.uid ?? '')
          .trim();
      if (resolvedUid.isNotEmpty) {
        await prefs.setString('user_uid', resolvedUid);
        await SessionHelper.saveSession(role, resolvedUid);
      }

      // Actualizar token FCM para que quede vinculado al usuario correcto
      try {
        await FcmService.instance.refreshToken();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error al guardar sesión: $e');
    }
  }

  /// Login con email y contraseña.
  /// Opcionalmente recibe el rol para persistirlo junto con el uid.
  Future<UserCredential?> loginWithEmailAndPassword({
    required String email,
    required String password,
    String? role,
  }) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        // Si se proporciona rol, guardar sesión completa (rol + uid)
        if (role != null && role.isNotEmpty) {
          await SessionHelper.saveSession(role, user.uid);
        } else {
          // Si no hay rol, marcar únicamente que está logueado
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_logged_in', true);
        }

        // Registrar/actualizar token FCM para el nuevo usuario
        try {
          await FcmService.instance.refreshToken();
        } catch (_) {}
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error de autenticación (login): ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error inesperado en login: $e');
      rethrow;
    }
  }

  /// Logout sencillo: delega en clearSession y limpia también SessionHelper.
  Future<void> logout() async {
    try {
      await clearSession();
      try {
        await SessionHelper.clearSession();
      } catch (_) {}
      try {
        await SessionHelper.clearActiveSolicitud();
      } catch (_) {}
    } catch (e) {
      debugPrint('Error al hacer logout: $e');
    }
  }

  Future<void> _clearPersistedSessionAndCaches(SharedPreferences prefs) async {
    await _safeRemovePref(prefs, 'is_logged_in');
    await _safeRemovePref(prefs, 'user_role');
    await _safeRemovePref(prefs, 'user_uid');
    await _safeRemovePref(prefs, 'cached_user_name');
    await _safeRemovePref(prefs, 'conductor_solicitud_activa');
    await _safeRemovePref(prefs, 'cliente_solicitud_activa');
    await _safeRemovePref(prefs, 'active_solicitud_id');

    final keys = prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      if (key.startsWith('solicitud_progreso_') ||
          key.startsWith('route_cache_') ||
          key.startsWith('trip_cache_')) {
        await _safeRemovePref(prefs, key);
      }
    }
  }

  Future<void> _safeRemovePref(SharedPreferences prefs, String key) async {
    try {
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Obtiene el usuario actual de Firebase (puede ser null si no hay sesión).
  User? getCurrentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  String _normalizeEstadoCliente(String rawEstado) {
    final raw = rawEstado.toLowerCase().trim();
    final compact = raw.replaceAll('_', ' ').replaceAll('-', ' ');

    if (compact.contains('en ruta') || compact.contains('enruta')) {
      return 'en_ruta';
    }
    if (compact.contains('en camino') || compact.contains('encam')) {
      return 'en_camino';
    }
    if (compact.contains('en espera') || compact.contains('enespera')) {
      return 'en_espera';
    }
    if (compact.contains('cancel') || compact.contains('complet')) {
      return 'cerrada';
    }
    if (compact.contains('asignado') || compact.contains('assigned')) {
      return 'asignado';
    }
    return compact;
  }

  bool _isSolicitudActivaCliente(String estadoNormalizado) {
    return estadoNormalizado == 'asignado' ||
        estadoNormalizado == 'en_espera' ||
        estadoNormalizado == 'en_camino' ||
        estadoNormalizado == 'en_ruta';
  }

  Future<String?> _findActiveSolicitudIdForUser({
    required String uid,
    required String? role,
  }) async {
    final queries = <String>[];

    if (role == 'conductor') {
      queries.addAll(const [
        'conductor.id',
        'conductor.uid',
        'conductorId',
        'conductor_id',
        'assignedTo',
        'driverId',
      ]);
    } else {
      queries.addAll(const [
        'cliente.id',
        'cliente.uid',
        'clienteId',
        'cliente_id',
        'userId',
      ]);
    }

    // Si el rol es ambiguo, intentamos ambos lados para maximizar restauracion.
    if (role == null) {
      queries.addAll(const [
        'conductor.id',
        'conductor.uid',
        'conductorId',
        'conductor_id',
        'assignedTo',
        'driverId',
      ]);
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
        final estado = (data['status'] ?? data['estado'] ?? '')
            .toString()
            .toLowerCase();

        if (_isEstadoSolicitudCerrado(estado)) {
          continue;
        }

        return doc.id;
      }
    } catch (_) {}

    return null;
  }

  bool _isEstadoSolicitudCerrado(String estado) {
    return estado.contains('complet') ||
        estado.contains('cancel') ||
        estado.contains('finaliz');
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
    } catch (_) {}
  }
}
