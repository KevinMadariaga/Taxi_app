import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/services/detector_ubicacion_simulada.dart';

Position _posicion({required bool simulada}) => Position(
  latitude: 8.24,
  longitude: -73.35,
  timestamp: DateTime(2026, 9, 29),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: simulada,
);

void main() {
  late List<Object> reportes;
  late DetectorUbicacionSimulada detector;

  setUp(() {
    reportes = [];
    detector = DetectorUbicacionSimulada(
      reportar: (error, _, {reason}) => reportes.add(error),
    );
  });

  test('una ubicación real no se reporta', () {
    detector.revisar(_posicion(simulada: false), origen: 'tracking');
    expect(reportes, isEmpty);
  });

  test('una ubicación simulada se reporta a Crashlytics', () {
    detector.revisar(_posicion(simulada: true), origen: 'tracking');
    expect(reportes, hasLength(1));
    expect(reportes.single, isA<UbicacionSimuladaDetectada>());
  });

  test(
    'un solo reporte por origen aunque sigan llegando posiciones falsas',
    () {
      for (var i = 0; i < 5; i++) {
        detector.revisar(_posicion(simulada: true), origen: 'tracking');
      }
      detector.revisar(_posicion(simulada: true), origen: 'lectura puntual');
      expect(reportes, hasLength(2));
    },
  );
}
