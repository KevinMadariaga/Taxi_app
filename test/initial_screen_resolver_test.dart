import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/initial_screen_resolver.dart';

void main() {
  group('InitialScreenResolver.conductorInProgressForEstado', () {
    test('se activa cuando el estado normalizado es enRuta', () {
      expect(
        InitialScreenResolver.conductorInProgressForEstado(
          SolicitudEstado.enRuta,
        ),
        isTrue,
      );
    });

    test(
      'NO se activa con asignado/enEspera/enCamino (bug anterior: '
      '.contains("camino") lo activaba por accidente)',
      () {
        expect(
          InitialScreenResolver.conductorInProgressForEstado(
            SolicitudEstado.asignado,
          ),
          isFalse,
        );
        expect(
          InitialScreenResolver.conductorInProgressForEstado(
            SolicitudEstado.enEspera,
          ),
          isFalse,
        );
        expect(
          InitialScreenResolver.conductorInProgressForEstado(
            SolicitudEstado.enCamino,
          ),
          isFalse,
        );
      },
    );

    test('NO se activa con estados terminales', () {
      expect(
        InitialScreenResolver.conductorInProgressForEstado(
          SolicitudEstado.completado,
        ),
        isFalse,
      );
      expect(
        InitialScreenResolver.conductorInProgressForEstado(
          SolicitudEstado.cancelado,
        ),
        isFalse,
      );
    });
  });
}
