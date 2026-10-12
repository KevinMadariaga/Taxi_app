import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/entidades/estadistica_dia.dart';
import '../../dominio/repositorios/estadisticas_repository.dart';

/// Lee `estadisticas_diarias/{AAAA-MM-DD}` (lo escriben las Cloud Functions
/// `estadisticasSolicitudCreada` y `estadisticasSolicitudEstado`).
class EstadisticasRepositoryImpl implements EstadisticasRepository {
  EstadisticasRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static int _n(Object? v) => v is num ? v.toInt() : 0;

  static EstadisticaDia _deDoc(String id, Map<String, dynamic> d) {
    final p = id.split('-').map(int.tryParse).toList();
    final horas = d['porHora'];
    return EstadisticaDia(
      dia: DateTime(p[0] ?? 2000, p[1] ?? 1, p[2] ?? 1),
      creadas: _n(d['creadas']),
      completadas: _n(d['completadas']),
      canceladas: _n(d['canceladas']),
      sinRespuesta: _n(d['sinRespuesta']),
      clientesUnicos: d['clientes'] is List
          ? (d['clientes'] as List).length
          : 0,
      porHora: [
        for (var h = 0; h < 24; h++)
          horas is Map ? _n(horas[h.toString().padLeft(2, '0')]) : 0,
      ],
    );
  }

  @override
  Stream<List<EstadisticaDia>> watchUltimosDias(int dias) {
    final hoy = hoyColombia();
    final desde = DateTime(hoy.year, hoy.month, hoy.day - (dias - 1));
    // Por id (la fecha): sin índice compuesto y en orden cronológico.
    return _firestore
        .collection('estadisticas_diarias')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: claveDia(desde))
        .snapshots()
        .map(
          (snap) => completarDias(
            [for (final d in snap.docs) _deDoc(d.id, d.data())],
            hoy: hoy,
            n: dias,
          ),
        );
  }
}
