import 'package:taxi_app/data/models/solicitud_item.dart';

class PreviewSolicitud {
  final SolicitudItem solicitud;

  PreviewSolicitud(this.solicitud);

  factory PreviewSolicitud.fromSolicitud(SolicitudItem s) =>
      PreviewSolicitud(s);

  String get id => solicitud.id;
  String? get clientName => solicitud.nombreCliente;
  String? get clientPhotoUrl => solicitud.clienteFoto;
  String? get paymentMethod => solicitud.metodoPago;
  String? get comentarioCliente => solicitud.comentarioCliente;
  double? get valorServicio => solicitud.valorServicio;
  double? get valorContraoferta => solicitud.valorContraoferta;
  String? get estadoContraoferta => solicitud.estadoContraoferta;
  double? get distanciaKm => solicitud.distanciaKm;
}
