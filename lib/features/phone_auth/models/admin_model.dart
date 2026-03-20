import 'package:cloud_firestore/cloud_firestore.dart';

class AdminModel {
  const AdminModel({
    required this.uid,
    required this.nombre,
    required this.telefono,
    required this.foto,
    required this.gremio,
    this.gremioFoto = '',
    this.fechaRegistro,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String foto;
  final String gremio;
  final String gremioFoto;
  final DateTime? fechaRegistro;

  factory AdminModel.fromFirestore(String uid, Map<String, dynamic> data) {
    final timestamp = data['fechaRegistro'];
    return AdminModel(
      uid: uid,
      nombre: (data['nombre'] ?? '').toString(),
      telefono: (data['telefono'] ?? '').toString(),
      foto: (data['foto'] ?? '').toString(),
      gremio: (data['gremio'] ?? '').toString(),
      gremioFoto: (data['gremioFoto'] ?? '').toString(),
      fechaRegistro: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}
