import 'package:cloud_firestore/cloud_firestore.dart';

class DriverModel {
  const DriverModel({
    required this.idConductor,
    required this.nombre,
    required this.telefono,
    required this.placa,
    required this.fotoConductor,
    required this.fotoVehiculo,
    required this.adminId,
    required this.estado,
    this.fechaRegistro,
  });

  final String idConductor;
  final String nombre;
  final String telefono;
  final String placa;
  final String fotoConductor;
  final String fotoVehiculo;
  final String adminId;
  final String estado;
  final DateTime? fechaRegistro;

  factory DriverModel.fromFirestore(String id, Map<String, dynamic> data) {
    final timestamp = data['fechaRegistro'];
    return DriverModel(
      idConductor: (data['idConductor'] ?? id).toString(),
      nombre: (data['nombre'] ?? '').toString(),
      telefono: (data['telefono'] ?? '').toString(),
      placa: (data['placa'] ?? '').toString(),
      fotoConductor: (data['fotoConductor'] ?? '').toString(),
      fotoVehiculo: (data['fotoVehiculo'] ?? '').toString(),
      adminId: (data['adminId'] ?? '').toString(),
      estado: (data['estado'] ?? 'activo').toString(),
      fechaRegistro: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}
