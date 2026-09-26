import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dominio/entidades/calificacion_cliente.dart';
import '../../dominio/repositorios/calificacion_cliente_repository.dart';

class CalificacionClienteRepositoryImpl
    implements CalificacionClienteRepository {
  CalificacionClienteRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<CalificacionCliente?> obtener(String clienteId) async {
    final snap = await _firestore
        .collection('calificaciones_clientes')
        .doc(clienteId)
        .get();
    final data = snap.data();
    if (data == null) return null;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    if (total <= 0) return null;
    return CalificacionCliente(
      promedio: (data['promedio'] as num?)?.toDouble() ?? 0,
      total: total,
    );
  }
}
