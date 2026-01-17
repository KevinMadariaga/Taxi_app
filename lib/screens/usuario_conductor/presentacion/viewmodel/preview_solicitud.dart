import 'package:taxi_app/data/models/solicitud_id.dart';

class PreviewSolicitud {
  final SolicitudItem solicitud;

  PreviewSolicitud(this.solicitud);

  factory PreviewSolicitud.fromSolicitud(SolicitudItem s) => PreviewSolicitud(s);

  String get id => solicitud.id;
  String? get clientName => solicitud.nombreCliente;
  String? get paymentMethod => solicitud.metodoPago;
  double? get distanciaKm => solicitud.distanciaKm;
}
