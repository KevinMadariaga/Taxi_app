import 'package:cloud_firestore/cloud_firestore.dart';

import 'usuario_model.dart';

class SolicitudModel {
  final String id;
  final String estado;
  final UsuarioModel cliente;
  final UsuarioModel conductor;
  final DateTime? updatedAt;

  const SolicitudModel({
    required this.id,
    required this.estado,
    required this.cliente,
    required this.conductor,
    required this.updatedAt,
  });

  factory SolicitudModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    final updatedTs = data['updatedAt'];
    final rawEstado = data['estado'] ?? data['status'];

    return SolicitudModel(
      id: doc.id,
      estado: (rawEstado ?? '').toString().toLowerCase(),
      cliente: UsuarioModel.fromMap(data['cliente'] as Map<String, dynamic>?),
      conductor: UsuarioModel.fromMap(
        data['conductor'] as Map<String, dynamic>?,
      ),
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
    );
  }

  factory SolicitudModel.fromCacheMap(Map<String, dynamic> map) {
    final updated = map['updatedAt'];
    return SolicitudModel(
      id: (map['id'] ?? '').toString(),
      estado: (map['estado'] ?? '').toString().toLowerCase(),
      cliente: UsuarioModel.fromMap(map['cliente'] as Map<String, dynamic>?),
      conductor: UsuarioModel.fromMap(
        map['conductor'] as Map<String, dynamic>?,
      ),
      updatedAt: updated is int
          ? DateTime.fromMillisecondsSinceEpoch(updated)
          : null,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'estado': estado,
      'cliente': cliente.toMap(),
      'conductor': conductor.toMap(),
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  bool get hasBothLocations => cliente.hasLocation && conductor.hasLocation;
}
