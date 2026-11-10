import 'package:cloud_firestore/cloud_firestore.dart';

import '../dominio/conductores_presentes_repository.dart';
import '../dominio/disponibilidad_conductores.dart';

/// Lee `conductores_conectados`, acotada a la última hora: la colección guarda
/// a todo el que alguna vez se conectó. La frescura fina (5 min) la evalúa
/// [calcularDisponibilidad], porque un filtro fijado acá envejecería con la
/// pantalla abierta.
class ConductoresPresentesRepositoryImpl
    implements ConductoresPresentesRepository {
  ConductoresPresentesRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<List<ConductorPresente>> watch() {
    final desde = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 1)),
    );
    return _firestore
        .collection('conductores_conectados')
        .where('updatedAt', isGreaterThanOrEqualTo: desde)
        .snapshots()
        .map((snap) {
          final lista = <ConductorPresente>[];
          for (final doc in snap.docs) {
            final data = doc.data();
            final visto = data['updatedAt'];
            final ubicacion = data['ubicacion'];
            if (visto is! Timestamp || ubicacion is! Map) continue;
            final lat = ubicacion['lat'];
            final lng = ubicacion['lng'];
            if (lat is! num || lng is! num) continue;
            lista.add(
              ConductorPresente(
                lat: lat.toDouble(),
                lng: lng.toDouble(),
                esMoto: '${data['tipoVehiculo'] ?? ''}'.toLowerCase() == 'moto',
                visto: visto.toDate(),
              ),
            );
          }
          return lista;
        });
  }
}
