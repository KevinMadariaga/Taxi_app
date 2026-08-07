import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';

import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Servicio que maneja la verificación de sesión y redirección
/// a la pantalla correspondiente según el estado del usuario
class AuthService {
  AuthService();

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
      await clearPersistedSessionAndCaches(prefs);
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
        await clearPersistedSessionAndCaches(prefs);
      } catch (e, st) {
        ErrorReporter.report(e, st, reason: 'auth_service');
      }
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
      } catch (e, st) {
        debugPrint('Error al refrescar token FCM tras guardar sesión: $e');
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason:
              'AuthService: fallo al refrescar token FCM en saveUserSession',
        );
      }
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
        } catch (e, st) {
          debugPrint('Error al refrescar token FCM tras login: $e');
          FirebaseCrashlytics.instance.recordError(
            e,
            st,
            reason:
                'AuthService: fallo al refrescar token FCM en loginWithEmailAndPassword',
          );
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
  /// Cierra la sesión y deja el dispositivo limpio.
  ///
  /// El orden importa: lo que necesita `currentUser` o permisos de Firestore
  /// va ANTES del `signOut()` que hace [clearSession].
  ///
  /// Antes solo borraba SharedPreferences, y quedaban vivas tres cosas: el
  /// `fcmToken` en el documento del usuario (el dispositivo seguía recibiendo
  /// push de la cuenta cerrada, incluso del rol abandonado), las notificaciones
  /// ya mostradas en la bandeja, y el servicio de ubicación en segundo plano
  /// mandando GPS a Firestore.
  Future<void> logout() async {
    // 1. Desvincular el token FCM — requiere sesión activa.
    try {
      await FcmService.instance.desvincularTokenAlCerrarSesion();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'auth_service: desvincular fcm');
    }

    // 2. Cortar el tracking en segundo plano.
    try {
      await stopBackgroundTrackingService();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'auth_service: stop background');
    }

    // 3. Limpiar la bandeja de notificaciones.
    try {
      await NotificacionesServicio.instance.cancelAll();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'auth_service: cancelAll notif');
    }

    // 4. Recién ahora: caché local + signOut.
    try {
      await clearSession();
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
    } catch (e) {
      debugPrint('Error al hacer logout: $e');
    }
  }

  Future<void> clearPersistedSessionAndCaches(SharedPreferences prefs) async {
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
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'auth_service');
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
