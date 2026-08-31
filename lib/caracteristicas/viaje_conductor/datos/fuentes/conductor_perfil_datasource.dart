import 'package:cloud_firestore/cloud_firestore.dart';

/// Escucha `usuarios/{uid}` (perfil del conductor, NO la colección
/// `conductores` — esa es solo de lectura y casi sin uso, ver
/// `firestore.rules`) mientras el viaje está activo, para poder propagar un
/// cambio de nombre/foto/placa hecho a mitad de viaje (`editar_perfil.dart`)
/// hacia `solicitudes/{viajeId}.conductor`, que es la copia congelada que
/// realmente lee el cliente (las reglas no le permiten leer `usuarios/{uid}`
/// de otro usuario).
class ConductorPerfilDatasource {
  ConductorPerfilDatasource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<Map<String, dynamic>?> watch(String conductorId) {
    return _firestore
        .collection('usuarios')
        .doc(conductorId)
        .snapshots()
        .map((snap) => snap.data());
  }
}
