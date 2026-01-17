import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ruta_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ruta_destino_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/home_conductor_map_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/ruta_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/ruta_destino_conductor.dart';
import 'package:taxi_app/services/route_cache_service.dart';

/// Servicio que maneja la verificación de sesión y redirección
/// a la pantalla correspondiente según el estado del usuario
class AuthService {
  AuthService();

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
      final activeFromRouteCache = await RouteCacheService.getActiveSolicitudId();

      // Verificar autenticación
      final currentUser = FirebaseAuth.instance.currentUser;
      final isLogged = prefs.getBool('is_logged_in') ?? false;
      String? role = prefs.getString('user_role');

      // Si hay un usuario autenticado, intentar detectar su rol basado en Firestore
      if (currentUser != null) {
        try {
          final uid = currentUser.uid;
          final conductorDoc = await FirebaseFirestore.instance.collection('conductor').doc(uid).get();
          if (conductorDoc.exists) {
            role = 'conductor';
          } else {
            final clienteDoc = await FirebaseFirestore.instance.collection('cliente').doc(uid).get();
            if (clienteDoc.exists) role = 'cliente';
          }
        } catch (_) {}
      }

      // Determinar id de solicitud candidata (SessionHelper tiene prioridad)
      String? candidateSolicitudId;
      if (activeFromSession != null && activeFromSession.isNotEmpty) {
        candidateSolicitudId = activeFromSession;
      } else if (activeFromRouteCache != null && activeFromRouteCache.isNotEmpty) {
        candidateSolicitudId = activeFromRouteCache;
      } else if (role == 'conductor') {
        candidateSolicitudId = solicitudActivaConductor;
      } else {
        candidateSolicitudId = solicitudActivaCliente;
      }

      // Si el usuario está autenticado
      if (currentUser != null || isLogged) {
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

        // 2) Si no hay solicitud activa válida, ir a la pantalla principal según rol
        return _getAuthenticatedUserScreen(role: role);
      }

      // Si no está autenticado, de forma opcional intentar restaurar por solicitud activa
      if (candidateSolicitudId != null && candidateSolicitudId.isNotEmpty) {
        final screen = await _buildScreenForActiveSolicitud(
          solicitudId: candidateSolicitudId,
          role: role,
        );
        if (screen != null) {
          return screen;
        }
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
  Widget _getAuthenticatedUserScreen({
    required String? role,
  }) {
    if (role == 'conductor') {
      // Usuario conductor sin solicitud activa
      return const HomeConductorMapView();
    } else {
      // Usuario cliente (rol == 'cliente' o null) sin solicitud activa
      return const InicioClienteView();
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
        try { await SessionHelper.clearActiveSolicitud(); } catch (_) {}
        return null;
      }

      final data = doc.data();
      if (data == null) return null;

      final estado = (data['status'] ?? data['estado'] ?? '')
          .toString()
          .toLowerCase();

      // No restaurar si está completada o cancelada
      if (estado.contains('complet') || estado.contains('cancel') || estado.contains('finaliz')) {
        try { await SessionHelper.clearActiveSolicitud(); } catch (_) {}
        return null;
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      // Resolver ids de conductor y cliente desde el documento
      String? conductorId;
      final rawConductor = data['conductor'];
      if (rawConductor is Map) {
        conductorId = (rawConductor['id'] ??
                rawConductor['uid'] ??
                rawConductor['conductorId'] ??
                rawConductor['driverId'])
            ?.toString();
      } else {
        conductorId = (data['conductorId'] ??
                data['conductor_id'] ??
                data['assignedTo'] ??
                data['driverId'])
            ?.toString();
      }

      String? clienteId;
      final rawCliente = data['cliente'];
      if (rawCliente is Map) {
        clienteId = (rawCliente['id'] ??
                rawCliente['uid'] ??
                rawCliente['clienteId'])
            ?.toString();
      } else {
        clienteId = (data['clienteId'] ?? data['userId'] ?? data['cliente_id'])
            ?.toString();
      }

      final isCurrentDriver =
          conductorId != null && currentUid != null && currentUid == conductorId;
      final isCurrentClient =
          clienteId != null && currentUid != null && currentUid == clienteId;

      // Conductor: rol explícito o coincide con el asignado
      if (role == 'conductor' || isCurrentDriver) {
        final conductorInProgress = estado.contains('progr') ||
            estado.contains('en_progr') ||
            estado.contains('enruta') ||
            estado.contains('viaj') ||
            estado.contains('camino') ||
            estado.contains('encam');

        if (conductorInProgress) {
          // intentar obtener ubicación de destino si está disponible en el documento
          LatLng? destino;
          try {
            final rawDestino = data['destino'] ?? data['destination'];
            if (rawDestino is Map) {
              final u = (rawDestino['ubicacion'] ?? rawDestino);
              if (u is Map) {
                final lat = (u['lat'] ?? u['latitude'] ?? u['latitud']);
                final lng = (u['lng'] ?? u['longitude'] ?? u['longitud']);
                if (lat != null && lng != null) {
                  destino = LatLng((lat as num).toDouble(), (lng as num).toDouble());
                }
              }
            }
          } catch (_) {}

          return RutaDestinoConductorView(
            solicitudId: solicitudId,
            destinoLocation: destino,
          );
        }
        // Try to restore cached route data to preserve UI state after reload (non in-progress)
        try {
          final cache = await RouteCacheService.loadForSolicitud(solicitudId);
          if (cache != null) {
            LatLng? clientLoc;
            if (cache.clientLat != null && cache.clientLng != null) {
              clientLoc = LatLng(cache.clientLat!, cache.clientLng!);
            }
            return RutaConductorView(
              solicitudId: solicitudId,
              clientLocation: clientLoc,
              clientName: cache.clientName,
              clientAddress: cache.clientAddress,
            );
          }
        } catch (_) {}

        return RutaConductorView(
          solicitudId: solicitudId,
        );
      }

      // Cliente: rol explícito, rol desconocido o coincide con el cliente
      if (role == 'cliente' || role == null || isCurrentClient) {
        final inProgress = estado.contains('progr') ||
          estado.contains('en_progr') ||
          estado.contains('enruta') ||
          estado.contains('viaj') ||
          // Variantes comunes de "en camino"
          estado.contains('camino') ||
          estado.contains('encam');

        if (inProgress) {
          // intentar obtener ubicación de destino si está disponible en el documento
          LatLng? destino;
          try {
            final rawDestino = data['destino'] ?? data['destination'];
            if (rawDestino is Map) {
              final u = (rawDestino['ubicacion'] ?? rawDestino);
              if (u is Map) {
                final lat = (u['lat'] ?? u['latitude'] ?? u['latitud']);
                final lng = (u['lng'] ?? u['longitude'] ?? u['longitud']);
                if (lat != null && lng != null) {
                  destino = LatLng((lat as num).toDouble(), (lng as num).toDouble());
                }
              }
            }
          } catch (_) {}

          return RutaDestinoClienteView(
            solicitudId: solicitudId,
            destinoLocation: destino,
          );
        }

        return RutaClienteView(
          solicitudId: solicitudId,
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('user_role');
      await prefs.remove('conductor_solicitud_activa');
      await prefs.remove('cliente_solicitud_activa');

      // Remover todas las solicitudes de cliente
      for (String key in prefs.getKeys()) {
        if (key.startsWith('solicitud_progreso_')) {
          await prefs.remove(key);
        }
      }

      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error al limpiar sesión: $e');
    }
  }

  /// Guarda la información de sesión del usuario
  Future<void> saveUserSession({
    required String role,
    required bool isLoggedIn,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', isLoggedIn);
      await prefs.setString('user_role', role);
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
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

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
      await SessionHelper.clearSession();
      await SessionHelper.clearActiveSolicitud();

      // Remove any persisted route caches to avoid restoring another user's data
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys().toList();
        for (final k in keys) {
          if (k.startsWith('route_cache_')) {
            await prefs.remove(k);
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error al hacer logout: $e');
    }
  }

  /// Obtiene el usuario actual de Firebase (puede ser null si no hay sesión).
  User? getCurrentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }
}
