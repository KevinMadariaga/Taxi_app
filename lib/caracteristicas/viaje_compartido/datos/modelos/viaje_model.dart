import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/participante_viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

/// Único parser del documento `solicitudes/{id}` para el flujo de viaje
/// activo — reemplaza los tres parsers que coexistían por separado
/// (`SolicitudModel`, `DriverTripModel`/`DriverTripParty`, y el parseo
/// crudo de mapas en `RutaDestinoViewModel.cargarDatosCliente`), todos con
/// la misma lógica de fallback de claves reimplementada cada uno por su
/// lado.
class ViajeModel {
  ViajeModel._();

  static ViajeEntity fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return fromMap(id: doc.id, data: data);
  }

  static ViajeEntity fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final updatedTs = data['updatedAt'];
    final rawEstado = data['estado'] ?? data['status'];
    final clienteMap = _asStringMap(data['cliente']);
    final conductorMap = _asStringMap(data['conductor']);
    final destinoMap = _asStringMap(data['destino']);
    final tarifaMap = _asStringMap(data['tarifa']);

    return ViajeEntity(
      id: id,
      estado: SolicitudEstado.normalize((rawEstado ?? '').toString()),
      cliente: _participanteFromMap(clienteMap),
      conductor: _participanteFromMap(conductorMap),
      destino: _destinoFromMap(data: data, destinoMap: destinoMap),
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
      valorServicio: _toDouble(
        tarifaMap?['total'] ??
            data['valorServicio'] ??
            data['valor'] ??
            data['tarifaTotal'] ??
            data['precio'],
      ),
      metodoPago:
          (data['paymentMethod'] ??
                  data['metodoPago'] ??
                  data['metodo_pago'] ??
                  '')
              .toString(),
      isMoto:
          (data['tipoVehiculo'] ?? data['tipo_vehiculo'] ?? '')
              .toString()
              .trim()
              .toLowerCase() ==
          'moto',
    );
  }

  static ParticipanteViajeEntity _participanteFromMap(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return ParticipanteViajeEntity.vacio;

    final ubicacionMap = _asStringMap(data['ubicacion']);
    double? lat = _toDoubleOrNull(
      ubicacionMap?['lat'] ?? ubicacionMap?['latitude'],
    );
    double? lng = _toDoubleOrNull(
      ubicacionMap?['lng'] ??
          ubicacionMap?['longitude'] ??
          ubicacionMap?['longitud'],
    );

    lat ??= _toDoubleOrNull(data['lat'] ?? data['latitude']);
    lng ??= _toDoubleOrNull(
      data['lng'] ?? data['longitude'] ?? data['longitud'],
    );

    final foto =
        data['foto'] ??
        data['photo'] ??
        data['photoUrl'] ??
        data['imagen'] ??
        '';
    final fotoVehiculo =
        data['fotoVehiculo'] ??
        data['foto_carro'] ??
        data['vehiclePhotoUrl'] ??
        data['fotoAuto'] ??
        '';
    final placaVehiculo =
        data['placa'] ??
        data['placaVehiculo'] ??
        data['vehiclePlate'] ??
        data['placa_auto'] ??
        '';

    return ParticipanteViajeEntity(
      id: (data['id'] ?? data['uid'] ?? data['conductorId'] ?? '').toString(),
      nombre: (data['nombre'] ?? data['name'] ?? '').toString(),
      fotoUrl: foto.toString(),
      fotoVehiculoUrl: fotoVehiculo.toString(),
      placaVehiculo: placaVehiculo.toString(),
      calificacion:
          _toDoubleOrNull(
            data['calificacionPromedio'] ??
                data['calificacion'] ??
                data['rating'],
          ) ??
          0,
      totalCalificaciones: _toInt(
        data['totalCalificaciones'] ??
            data['totalRatings'] ??
            data['ratingCount'],
      ),
      direccion: _firstNonEmptyText([
        ubicacionMap?['direccion'],
        ubicacionMap?['address'],
        ubicacionMap?['texto'],
        ubicacionMap?['title'],
        ubicacionMap?['address_text'],
        ubicacionMap?['formatted_address'],
        ubicacionMap?['descripcion'],
        data['direccion'],
        data['origenTitle'],
        data['address'],
        data['direccion_recoger'],
        data['direccion_origen'],
      ]),
      ubicacion: (lat != null && lng != null) ? LatLng(lat, lng) : null,
    );
  }

  /// Primer texto no vacío de la lista — mismo criterio de fallback que
  /// usaba `DriverTripParty._firstText`: la dirección puede venir en
  /// distintas claves según qué flujo escribió el documento (app cliente,
  /// legacy, cloud function, etc.), así que se prueban todas antes de
  /// rendirse a `''`.
  static String _firstNonEmptyText(Iterable<dynamic> candidates) {
    for (final raw in candidates) {
      if (raw == null) continue;
      final text = raw.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static DestinoViajeEntity _destinoFromMap({
    required Map<String, dynamic> data,
    required Map<String, dynamic>? destinoMap,
  }) {
    final lat = _toDoubleOrNull(destinoMap?['lat'] ?? destinoMap?['latitude']);
    final lng = _toDoubleOrNull(
      destinoMap?['lng'] ?? destinoMap?['longitude'] ?? destinoMap?['longitud'],
    );

    final direccion =
        (data['destinoDireccion'] ??
                destinoMap?['direccion'] ??
                destinoMap?['title'] ??
                destinoMap?['address'] ??
                '')
            .toString();

    return DestinoViajeEntity(
      direccion: direccion,
      ubicacion: (lat != null && lng != null) ? LatLng(lat, lng) : null,
    );
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _toDoubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
