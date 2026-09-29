import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Se registra en Crashlytics cuando el GPS del conductor viene de una app de
/// ubicación falsa (mock location / GPS spoofing).
class UbicacionSimuladaDetectada implements Exception {
  const UbicacionSimuladaDetectada(this.origen);

  /// Dónde se detectó: tracking del viaje, lectura puntual, etc.
  final String origen;

  @override
  String toString() => 'UbicacionSimuladaDetectada(origen: $origen)';
}

/// Detección de ubicación simulada (C1). Decisión de producto: **solo se
/// registra en Crashlytics**; la ubicación se sigue usando igual (no se
/// descarta ni se bloquea el modo conductor).
///
/// `Position.isMocked` lo informa Android; en iOS siempre es `false` salvo
/// casos puntuales, así que en la práctica cubre Android.
///
/// Un reporte por [origen] y por sesión de la app: con el GPS falso activo
/// llega una posición simulada cada pocos segundos y no hace falta un reporte
/// por cada una.
class DetectorUbicacionSimulada {
  DetectorUbicacionSimulada({
    void Function(Object error, StackTrace stackTrace, {String? reason})?
    reportar,
  }) : _reportar = reportar ?? ErrorReporter.report;

  static final DetectorUbicacionSimulada instance = DetectorUbicacionSimulada();

  final void Function(Object error, StackTrace stackTrace, {String? reason})
  _reportar;
  final Set<String> _yaReportado = <String>{};

  void revisar(Position position, {required String origen}) {
    if (!position.isMocked) return;
    if (!_yaReportado.add(origen)) return;
    _reportar(
      UbicacionSimuladaDetectada(origen),
      StackTrace.current,
      reason: 'Ubicación simulada (mock/GPS falso) detectada en $origen',
    );
  }
}
