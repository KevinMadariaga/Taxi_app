import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

import '../dominio/viaje_pendiente.dart';
import '../dominio/viaje_pendiente_repository.dart';

class ViajePendienteRepositoryImpl implements ViajePendienteRepository {
  ViajePendienteRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<List<ViajePendiente>> watch(String clienteId) => _firestore
      .collection('solicitudes')
      .where('cliente.id', isEqualTo: clienteId)
      .where(
        'estado',
        whereIn: const [
          SolicitudEstado.programada,
          SolicitudEstado.buscando,
          SolicitudEstado.asignado,
        ],
      )
      .snapshots()
      .map((snap) {
        final lista = <ViajePendiente>[];
        for (final doc in snap.docs) {
          final data = doc.data();
          final tipo = ViajePendiente.tipoDe(
            '${data['estado'] ?? ''}',
            data['avisarAlEncontrar'] == true,
          );
          if (tipo == null) continue;
          final destino = data['destino'];
          lista.add(
            ViajePendiente(
              id: doc.id,
              tipo: tipo,
              destino: destino is Map
                  ? '${destino['title'] ?? destino['address'] ?? destino['direccion'] ?? ''}'
                  : '',
              programadaPara: (data['programadaPara'] as Timestamp?)?.toDate(),
              tipoVehiculo: data['tipoVehiculo']?.toString(),
            ),
          );
        }
        lista.sort(
          (a, b) => (a.programadaPara ?? DateTime(0)).compareTo(
            b.programadaPara ?? DateTime(0),
          ),
        );
        return lista;
      });

  @override
  Future<void> cancelar(String id) =>
      _firestore.collection('solicitudes').doc(id).update({
        'estado': SolicitudEstado.cancelado,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': 'cliente',
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
