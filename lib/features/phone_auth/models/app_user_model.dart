import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserModel {
  const AppUserModel({
    required this.uid,
    required this.nombre,
    required this.telefono,
    required this.foto,
    required this.rol,
    this.fechaRegistro,
  });

  final String uid;
  final String nombre;
  final String telefono;
  final String foto;
  final String rol;
  final DateTime? fechaRegistro;

  factory AppUserModel.fromFirestore(String uid, Map<String, dynamic> data) {
    final timestamp = data['fechaRegistro'];
    return AppUserModel(
      uid: uid,
      nombre: (data['nombre'] ?? '').toString(),
      telefono: (data['telefono'] ?? '').toString(),
      foto: (data['foto'] ?? '').toString(),
      rol: (data['rol'] ?? '').toString(),
      fechaRegistro: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'nombre': nombre,
      'telefono': telefono,
      'foto': foto,
      'rol': rol,
      'fechaRegistro': FieldValue.serverTimestamp(),
    };
  }
}
