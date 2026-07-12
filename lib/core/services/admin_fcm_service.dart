import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_remote_config_service.dart';

/// Envía notificaciones push FCM a todos los administradores registrados.
///
/// Usa la Legacy FCM HTTP API. El server key debe estar configurado en
/// Firebase Remote Config bajo la clave `fcm_server_key`.
class AdminFcmService {
  AdminFcmService._();
  static final AdminFcmService instance = AdminFcmService._();

  static const String _fcmUrl = 'https://fcm.googleapis.com/fcm/send';

  Future<void> sendToAllAdmins({
    required String title,
    required String body,
    String type = 'admin_notification',
  }) async {
    String? serverKey;
    try {
      serverKey = await AppRemoteConfigService.instance.fetchFcmServerKey();
    } catch (e, st) {
      debugPrint('[AdminFcm] Error obteniendo fcm_server_key: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'AdminFcmService: fallo al obtener fcm_server_key desde Remote Config (sendToAllAdmins)',
      );
    }

    if (serverKey == null || serverKey.isEmpty) {
      debugPrint('[AdminFcm] fcm_server_key no configurado en Remote Config');
      return;
    }

    List<String> tokens = [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('administradores')
          .get();
      tokens = snap.docs
          .map((d) => (d.data()['fcmToken'] as String?) ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[AdminFcm] Error leyendo tokens admin: $e');
      return;
    }

    if (tokens.isEmpty) {
      debugPrint('[AdminFcm] Sin tokens FCM de admins');
      return;
    }

    for (final token in tokens) {
      try {
        final response = await http.post(
          Uri.parse(_fcmUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'key=$serverKey',
          },
          body: jsonEncode({
            'to': token,
            'priority': 'high',
            'notification': {
              'title': title,
              'body': body,
              'sound': 'default',
              'android_channel_id': 'taxi_admin_channel',
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'taxi_admin_channel',
                'default_sound': true,
                'default_vibrate_timings': true,
                'notification_priority': 'PRIORITY_MAX',
              },
            },
            'apns': {
              'payload': {
                'aps': {'sound': 'default'},
              },
            },
            'data': {
              'type': type,
              'title': title,
              'body': body,
            },
          }),
        );
        debugPrint('[AdminFcm] Enviado a $token — status ${response.statusCode}');
      } catch (e) {
        debugPrint('[AdminFcm] Error enviando a $token: $e');
      }
    }
  }

  /// Envía una notificación push a un token FCM individual (p.ej. conductor).
  Future<void> sendToToken({
    required String token,
    required String title,
    required String body,
    String type = 'notification',
    Map<String, String> extraData = const {},
  }) async {
    if (token.isEmpty) return;

    String? serverKey;
    try {
      serverKey = await AppRemoteConfigService.instance.fetchFcmServerKey();
    } catch (e, st) {
      debugPrint('[AdminFcm] Error obteniendo fcm_server_key: $e');
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'AdminFcmService: fallo al obtener fcm_server_key desde Remote Config (sendToToken)',
      );
    }

    if (serverKey == null || serverKey.isEmpty) {
      debugPrint('[AdminFcm] fcm_server_key no configurado en Remote Config');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(_fcmUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'to': token,
          'priority': 'high',
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
          },
          'data': {
            'type': type,
            'title': title,
            'body': body,
            ...extraData,
          },
        }),
      );
      debugPrint('[AdminFcm] Token individual — status ${response.statusCode}');
    } catch (e) {
      debugPrint('[AdminFcm] Error enviando token individual: $e');
    }
  }
}
