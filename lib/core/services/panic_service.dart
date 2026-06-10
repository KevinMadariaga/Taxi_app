import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Escribe una emergencia de pánico en la colección `emergencias`.
/// El admin puede verla en AdminHubScreen o en una pantalla dedicada futura.
class PanicService {
  PanicService._();
  static final PanicService instance = PanicService._();

  Future<void> enviarEmergencia({
    required String userId,
    required String solicitudId,
    LatLng? ubicacion,
    List<String> motivos = const [],
    String comentario = '',
  }) async {
    try {
      await FirebaseFirestore.instance.collection('emergencias').add({
        'userId': userId,
        'solicitudId': solicitudId,
        'lat': ubicacion?.latitude,
        'lng': ubicacion?.longitude,
        'motivos': motivos,
        'comentario': comentario,
        'timestamp': FieldValue.serverTimestamp(),
        'tipo': 'panico',
        'atendido': false,
      });
      debugPrint('[PanicService] Emergencia enviada para $userId');
    } catch (e) {
      debugPrint('[PanicService] Error: $e');
      rethrow;
    }
  }
}
