import 'package:cloud_firestore/cloud_firestore.dart';

class SugerenciasService {
  SugerenciasService._();
  static final SugerenciasService instance = SugerenciasService._();

  final _fs = FirebaseFirestore.instance;

  Future<void> enviar({
    required String userId,
    required String tipo, // 'cliente' | 'conductor'
    required String mensaje,
    int estrellas = 0,
  }) async {
    await _fs.collection('sugerencias').add({
      'userId': userId,
      'tipo': tipo,
      'mensaje': mensaje,
      'estrellas': estrellas,
      'creadoEn': FieldValue.serverTimestamp(),
      'visto': false,
    });
  }

  Future<void> marcarVisto(String docId) async {
    await _fs.collection('sugerencias').doc(docId).update({'visto': true});
  }

  /// Cantidad de sugerencias sin revisar (badge de `AdminHubScreen`).
  Stream<int> watchNoVistasCount() {
    return _fs
        .collection('sugerencias')
        .where('visto', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAll() {
    return _fs
        .collection('sugerencias')
        .orderBy('creadoEn', descending: true)
        .snapshots();
  }
}
