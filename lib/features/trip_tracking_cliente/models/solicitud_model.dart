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
    final clienteMap = _asStringMap(data['cliente']);
    final conductorMap = _asStringMap(data['conductor']);

    return SolicitudModel(
      id: doc.id,
      estado: (rawEstado ?? '').toString().toLowerCase(),
      cliente: UsuarioModel.fromMap(clienteMap),
      conductor: UsuarioModel.fromMap(conductorMap),
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
    );
  }

  factory SolicitudModel.fromCacheMap(Map<String, dynamic> map) {
    final updated = map['updatedAt'];
    final clienteMap = _asStringMap(map['cliente']);
    final conductorMap = _asStringMap(map['conductor']);
    return SolicitudModel(
      id: (map['id'] ?? '').toString(),
      estado: (map['estado'] ?? '').toString().toLowerCase(),
      cliente: UsuarioModel.fromMap(clienteMap),
      conductor: UsuarioModel.fromMap(conductorMap),
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

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }
}
