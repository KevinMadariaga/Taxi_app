import 'package:cloud_firestore/cloud_firestore.dart';

class SolicitudItem {
  final String id;
  final String? clienteId;
  final GeoPoint ubicacionInicial;
  GeoPoint? ubicacionDestino;
  String? metodoPago;
  String? nombreCliente;
  String? comentarioCliente;
  String? clienteFoto;
  String? direccion; // origin title/address
  String? origenTitle;
  String? destinoTitle;
  double? valorServicio;
  double? valorContraoferta;
  String? estadoContraoferta;
  double? distanciaKm;
  String? tipoVehiculo;

  SolicitudItem({
    required this.id,
    required this.clienteId,
    required this.ubicacionInicial,
    this.ubicacionDestino,
    this.metodoPago,
    this.nombreCliente,
    this.comentarioCliente,
    this.clienteFoto,
    this.direccion,
    this.origenTitle,
    this.destinoTitle,
    this.valorServicio,
    this.valorContraoferta,
    this.estadoContraoferta,
    this.distanciaKm,
    this.tipoVehiculo,
  });

  /// [conductorUid] es el conductor que está MIRANDO la solicitud. Se usa para
  /// resolver `contraofertas[uid]` (su propia oferta) en vez del campo legacy
  /// `contraoferta`, que guarda la ÚLTIMA oferta de cualquier conductor: sin
  /// esto, el conductor A veía la oferta de B rotulada como "Tu contraoferta".
  /// Si es `null` se cae al campo legacy (comportamiento anterior).
  factory SolicitudItem.fromMap(
    String id,
    Map<String, dynamic> map, {
    String? conductorUid,
  }) {
    final cliente = _asMap(map['cliente']);
    final clienteUbicacion = _asMap(cliente?['ubicacion']);
    final origen = _asMap(map['origen']);
    final destino = _asMap(map['destino']);
    final tarifa = _asMap(map['tarifa']);

    // Oferta propia (mapa nuevo por conductor) con fallback al campo legacy
    // solo cuando no se sabe quién mira.
    final contraofertasMap = _asMap(map['contraofertas']);
    final Map<String, dynamic>? contraoferta;
    if (conductorUid != null && conductorUid.isNotEmpty) {
      contraoferta = _asMap(contraofertasMap?[conductorUid]);
    } else {
      contraoferta = _asMap(map['contraoferta']);
    }

    String? clienteId = _firstText([
      cliente?['id'],
      cliente?['uid'],
      cliente?['clienteId'],
      map['clienteId'],
    ]);

    String? nombreCliente = _firstText([
      cliente?['nombre'],
      cliente?['name'],
      map['clienteNombre'],
      map['cliente_name'],
      map['nombre_cliente'],
    ]);

    GeoPoint ubicacionInicial =
        _toGeoPoint(clienteUbicacion) ??
        (map['ubicacion_inicial'] is GeoPoint
            ? map['ubicacion_inicial'] as GeoPoint
            : null) ??
        _toGeoPoint(origen) ??
        const GeoPoint(0, 0);

    final origenTitle = _firstText([
      origen?['title'],
      origen?['address'],
      origen?['direccion'],
      origen?['address_text'],
      clienteUbicacion?['address'],
      clienteUbicacion?['direccion'],
      map['direccion'],
      map['direccion_recoger'],
      map['direccion_origen'],
      map['ubicacion_text'],
    ]);

    GeoPoint? ubicacionDestino;
    String? destinoTitle;
    final destinoRaw = map['destino'];
    if (destinoRaw is GeoPoint) {
      ubicacionDestino = destinoRaw;
    } else {
      ubicacionDestino = _toGeoPoint(destino);
      destinoTitle = _firstText([
        destino?['title'],
        destino?['address'],
        destino?['direccion'],
      ]);
    }

    final metodo = _firstText([
      map['metodo'],
      map['metodoPago'],
      map['metodo_pago'],
    ]);

    final calificacion = _asMap(map['calificacion']);

    final comentarioCliente = _firstCommentText([
      map['comentario'],
      map['comentarioCliente'],
      map['comentario_cliente'],
      map['comentarioCalificacion'],
      calificacion?['comentario'],
      calificacion?['comentarioCalificacion'],
      calificacion?['comentario_cliente'],
      cliente?['comentario'],
      cliente?['comentarioCalificacion'],
    ]);

    // Try to extract client photo from nested cliente object or common fields
    String? clienteFoto = _firstText([
      cliente?['foto'],
      cliente?['fotoUrl'],
      cliente?['photoUrl'],
      cliente?['imagen'],
      map['clienteFoto'],
      map['cliente_foto'],
    ]);

    final direccion = origenTitle;

    final valorServicio =
        _toDouble(tarifa?['total']) ??
        _toDouble(map['valorServicioPropuesto']) ??
        _toDouble(map['valor']);
    final valorContraoferta = _toDouble(contraoferta?['valor']);
    // `estadoContraoferta` de nivel superior es GLOBAL (lo pisa el último
    // conductor que oferta), así que solo sirve de fallback cuando no se sabe
    // quién está mirando. Con `conductorUid` conocido, el estado sale
    // exclusivamente de su propia entrada — si no tiene, no hay contraoferta
    // suya que mostrar.
    final estadoContraoferta = (conductorUid != null && conductorUid.isNotEmpty)
        ? _firstText([contraoferta?['estado']])
        : _firstText([contraoferta?['estado'], map['estadoContraoferta']]);

    return SolicitudItem(
      id: id,
      clienteId: clienteId,
      ubicacionInicial: ubicacionInicial,
      ubicacionDestino: ubicacionDestino,
      metodoPago: metodo,
      nombreCliente: nombreCliente,
      comentarioCliente: comentarioCliente,
      clienteFoto: clienteFoto,
      direccion: direccion,
      origenTitle: origenTitle,
      destinoTitle: destinoTitle,
      valorServicio: valorServicio,
      valorContraoferta: valorContraoferta,
      estadoContraoferta: estadoContraoferta,
      distanciaKm: (map['distanciaKm'] is num)
          ? (map['distanciaKm'] as num).toDouble()
          : null,
      tipoVehiculo: map['tipoVehiculo']?.toString(),
    );
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String? _firstCommentText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) continue;

      final lower = text.toLowerCase();
      if (lower == 'null' ||
          lower == 'sin comentario' ||
          lower == 'ninguno' ||
          lower == 'n/a' ||
          lower == 'na' ||
          text == '-') {
        continue;
      }

      return text;
    }
    return null;
  }

  static GeoPoint? _toGeoPoint(Map<String, dynamic>? value) {
    if (value == null) return null;
    final lat = _toDouble(value['lat'] ?? value['latitude']);
    final lng = _toDouble(
      value['lng'] ?? value['longitude'] ?? value['longitud'],
    );
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
