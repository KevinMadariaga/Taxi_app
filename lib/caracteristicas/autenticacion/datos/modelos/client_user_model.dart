import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';

class ClientUserModel extends ClientUserEntity {
  const ClientUserModel({
    required super.id,
    required super.nombre,
    required super.apellido,
    required super.telefono,
    required super.fotoUrl,
    required super.rol,
    required super.isProfileComplete,
    required super.createdAt,
    super.email,
  });

  factory ClientUserModel.fromFirestore(String id, Map<String, dynamic> data) {
    final createdAtRaw = data['createdAt'] ?? data['fechaRegistro'];

    DateTime createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    } else {
      createdAt = DateTime.now();
    }

    return ClientUserModel(
      id: id,
      nombre: (data['nombre'] ?? '').toString().trim(),
      apellido: (data['apellido'] ?? '').toString().trim(),
      telefono: (data['telefono'] ?? '').toString().trim(),
      fotoUrl: (data['fotoUrl'] ?? data['foto'] ?? '').toString().trim(),
      rol: (data['rol'] ?? 'cliente').toString().trim(),
      email: (data['email'] ?? '').toString().trim().isEmpty
          ? null
          : (data['email'] ?? '').toString().trim(),
      isProfileComplete: data['isProfileComplete'] == true,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'uid': id,
      'nombre': nombre,
      'apellido': apellido,
      'telefono': telefono,
      'fotoUrl': fotoUrl,
      'rol': rol,
      'email': email,
      'isProfileComplete': isProfileComplete,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
