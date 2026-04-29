import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DestinoSeleccionViewModel extends ChangeNotifier {
  DestinoSeleccionViewModel({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Devuelve favoritos guardados del usuario filtrados por [tipo].
  Future<List<Map<String, dynamic>>> getFavoritosPorTipo(String tipo) async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('favoritos')
        .where('tipo', isEqualTo: tipo)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Devuelve el primer favorito de tipo Casa o Trabajo, si existe.
  Future<Map<String, dynamic>?> getFavoritoUnico(String tipo) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('favoritos')
        .where('tipo', isEqualTo: tipo)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return {'id': snap.docs.first.id, ...snap.docs.first.data()};
  }

  /// Guarda una ubicación personalizada en favoritos del usuario.
  Future<void> guardarUbicacion(
    String tipo,
    LatLng loc, {
    String? nombrePersonalizado,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    String direccion = '';
    try {
      final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        direccion = [p.street, p.subLocality, p.locality, p.administrativeArea]
            .where((s) => (s ?? '').isNotEmpty)
            .join(', ');
      }
    } catch (_) {}

    if (direccion.isEmpty) {
      direccion =
          '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
    }

    final payload = {
      'userId': uid,
      'nombre': nombrePersonalizado ?? tipo,
      'direccion': direccion,
      'ubicacion': GeoPoint(loc.latitude, loc.longitude),
      'createdAt': FieldValue.serverTimestamp(),
      'tipo': tipo,
    };

    await _firestore
        .collection('usuarios')
        .doc(uid)
        .collection('favoritos')
        .add(payload);

    // Compatibilidad con consultas legacy.
    await _firestore.collection('ubicaciones').add(payload);
  }
}
