import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dominio/tour_repository.dart';

/// El recorrido se ve UNA sola vez por cuenta, en cualquier teléfono.
///
/// La marca vive en `usuarios/{uid}.toursVistos.{tourId}` (Firestore), así
/// que no vuelve a salir al reinstalar, borrar datos o entrar desde otro
/// teléfono. SharedPreferences queda como caché local para no leer Firestore
/// en cada entrada al home.
class TourRepositoryImpl implements TourRepository {
  TourRepositoryImpl({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static String _clave(String tourId, String uid) =>
      'tour_visto_${tourId}_$uid';

  @override
  Future<bool> yaVisto(String tourId, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_clave(tourId, uid)) == true) return true;
    try {
      final doc = await _firestore.collection('usuarios').doc(uid).get();
      final vistos = doc.data()?['toursVistos'];
      final visto = vistos is Map && vistos[tourId] != null;
      if (visto) await prefs.setBool(_clave(tourId, uid), true);
      return visto;
    } catch (_) {
      // Sin poder confirmarlo (sin red), mejor no mostrarlo: se intenta en
      // la próxima entrada. Repetírselo a quien ya lo vio es peor.
      return true;
    }
  }

  @override
  Future<void> marcarVisto(String tourId, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clave(tourId, uid), true);
    // Sin await: con mala red Firestore lo encola y lo sube al reconectar;
    // el recorrido no debe esperar a la red para mostrarse.
    _firestore.collection('usuarios').doc(uid).set({
      'toursVistos': {tourId: FieldValue.serverTimestamp()},
    }, SetOptions(merge: true)).ignore();
  }
}
