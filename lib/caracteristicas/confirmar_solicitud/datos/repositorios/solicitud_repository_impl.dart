import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:taxi_app/core/constants/estado_contraoferta.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import '../../dominio/entidades/cliente_actual.dart';
import '../../dominio/repositorios/solicitud_repository.dart';

class SolicitudRepositoryImpl implements SolicitudRepository {
  SolicitudRepositoryImpl({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // 'pending'/'pendiente' son sinónimos legacy de `SolicitudEstado.buscando`
  // (ver mismo comentario en `SolicitudEstado.normalize`).
  static const _estadosActivos = [
    SolicitudEstado.buscando,
    'pending',
    'pendiente',
    SolicitudEstado.asignado,
    SolicitudEstado.enEspera,
    SolicitudEstado.enCamino,
    SolicitudEstado.enRuta,
  ];

  @override
  Future<String?> buscarActivaDeCliente(String clienteId) async {
    try {
      final existing = await _firestore
          .collection('solicitudes')
          .where('cliente.id', isEqualTo: clienteId)
          .where('estado', whereIn: _estadosActivos)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return existing.docs.first.id;
      return null;
    } catch (e, st) {
      // Se reporta y se PROPAGA. Devolver `null` acá hacía que el caso de uso
      // lo interpretara como "no hay solicitud activa" y creara otra: el
      // guard anti-duplicados fallaba abierto ante cualquier error transitorio
      // u offline. Quien llama decide qué hacer (hoy: abortar y avisar).
      ErrorReporter.report(e, st, reason: 'solicitud_repository_impl');
      rethrow;
    }
  }

  @override
  Future<String> crear({
    required ClienteActual cliente,
    required LocationModel origen,
    required String origenDireccion,
    required LocationModel destino,
    required String destinoDireccion,
    required VehicleType tipoVehiculo,
    required String metodoPago,
    required String comentario,
    required double valorServicio,
  }) async {
    final origenPos = origen.position;
    final destinoPos = destino.position;

    final solicitud = <String, dynamic>{
      'cliente': {
        'id': cliente.id,
        'nombre': cliente.nombre,
        'foto': cliente.fotoUrl ?? '',
        'ubicacion': {
          'lat': origenPos.latitude,
          'lng': origenPos.longitude,
          'direccion': origenDireccion,
        },
      },
      'origen': {
        'lat': origenPos.latitude,
        'lng': origenPos.longitude,
        'address': origenDireccion,
        'title': origenDireccion,
      },
      'ubicacion_inicial': GeoPoint(origenPos.latitude, origenPos.longitude),
      'destino': {
        'direccion': destinoDireccion,
        'lat': destinoPos.latitude,
        'lng': destinoPos.longitude,
      },
      'estado': SolicitudEstado.buscando,
      'tipoVehiculo': tipoVehiculo.firestoreKey,
      'metodoPago': metodoPago,
      'comentario': comentario,
      'valorServicioPropuesto': valorServicio,
      'estadoContraoferta': EstadoContraoferta.sinContraoferta,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'tarifa': {'total': valorServicio, 'propuestaCliente': valorServicio},
      'contraoferta': {
        'estado': EstadoContraoferta.sinContraoferta,
        'valor': null,
      },
    };

    final docRef = await _firestore.collection('solicitudes').add(solicitud);
    return docRef.id;
  }
}
