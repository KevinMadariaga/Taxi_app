import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/cancelar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/dominio/casos_uso/confirmar_voy_en_camino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/viewmodels/viaje_cliente_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_cliente/presentacion/widgets/trip_info_card/trip_info_card.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/participante_viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/controladores/chat_controller.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/trip_card_metrics.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

import 'test_helpers/firebase_test_setup.dart';

/// La tarjeta del cliente mide el alto de su contenido (píxeles fijos), no un
/// porcentaje de pantalla. Estos tests fijan que ese alto real entra bajo el
/// techo `TripCardMetrics.alturaMaximaFactor` en los tres tamaños de
/// pantalla que cubre la app — es decir, que el mapa nunca queda aplastado y
/// que la tarjeta no scrollea en un teléfono normal.
class _FakeViajeRepository implements ViajeRepository {
  @override
  Stream<ViajeEntity> watchViaje(String viajeId) => const Stream.empty();

  @override
  Future<void> actualizarEstado({
    required String viajeId,
    required String estado,
    Map<String, dynamic>? extra,
  }) async {}

  @override
  Future<void> cancelar({
    required String viajeId,
    required String canceladoPor,
  }) async {}

  @override
  Future<void> actualizarInfoConductor({
    required String viajeId,
    required Map<String, dynamic> datosConductor,
  }) async {}
}

const _conductor = ParticipanteViajeEntity(
  id: 'c1',
  nombre: 'Juan Carlos Rodríguez',
  fotoUrl: '',
  fotoVehiculoUrl: '',
  placaVehiculo: 'ABC123',
  calificacion: 4.87,
  totalCalificaciones: 42,
  direccion: 'Calle 1',
  ubicacion: LatLng(4.60, -74.08),
);

const _cliente = ParticipanteViajeEntity(
  id: 'u1',
  nombre: 'Ana',
  fotoUrl: '',
  fotoVehiculoUrl: '',
  placaVehiculo: '',
  calificacion: 5,
  totalCalificaciones: 3,
  direccion: 'Calle 2',
  ubicacion: LatLng(4.61, -74.07),
);

ViajeClienteViewModel _buildVm() {
  final repo = _FakeViajeRepository();
  final vm = ViajeClienteViewModel(
    viajeId: 'v1',
    clienteId: 'u1',
    watchViaje: WatchViajeUseCase(repo),
    confirmarVoyEnCamino: ConfirmarVoyEnCaminoUseCase(
      ActualizarEstadoViajeUseCase(repo),
    ),
    cancelarViaje: CancelarViajeUseCase(repo),
    rutaDatasource: RutaDatasource(),
    chatController: ChatController(
      viajeId: 'v1',
      currentUserId: 'u1',
      otherPartyLabel: 'conductor',
    ),
  );
  vm.viaje = ViajeEntity(
    id: 'v1',
    // El estado del enunciado: "Conductor llegando a tu ubicación".
    estado: SolicitudEstado.asignado,
    cliente: _cliente,
    conductor: _conductor,
    destino: DestinoViajeEntity.vacio,
    updatedAt: DateTime(2026, 1, 1),
  );
  return vm;
}

/// Renderiza la tarjeta con el alto de pantalla dado y devuelve su alto real,
/// medido igual que en `ViajeClienteScreen`: `SingleChildScrollView` dentro de
/// un `ConstrainedBox(maxHeight:)`, encogido al contenido.
Future<double> _alturaTarjeta(
  WidgetTester tester, {
  required Size pantalla,
  CodigoVerificacionEntity? codigo,
}) async {
  tester.view.physicalSize = pantalla;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Sin `vm.dispose()`: su `dispose` llama a `NotificacionesServicio`, que
  // necesita el plugin nativo. Acá el VM nunca se suscribe a nada (el
  // repositorio es un stream vacío), así que no hay nada que liberar.
  final vm = _buildVm();

  final metrics = TripCardMetrics.forHeight(pantalla.height);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: pantalla.height * metrics.alturaMaximaFactor,
              ),
              child: SingleChildScrollView(
                child: TripInfoCard(
                  vm: vm,
                  onChat: () {},
                  onDetails: () {},
                  onHelp: () {},
                  onCancel: () {},
                  codigoVerificacion: codigo,
                ),
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ),
  );

  return tester.getSize(find.byType(TripInfoCard)).height;
}

void main() {
  setUpAll(setupFirebaseForTests);

  const pantallas = <String, Size>{
    'compacta (iPhone SE)': Size(375, 667),
    'normal (iPhone 14)': Size(390, 844),
    'alta (Pixel 7 Pro)': Size(412, 915),
    'muy alta (tablet)': Size(800, 1280),
  };

  pantallas.forEach((nombre, size) {
    testWidgets('$nombre: la tarjeta cabe sin scroll y deja mapa', (
      tester,
    ) async {
      final alto = await _alturaTarjeta(tester, pantalla: size);
      final techo =
          size.height * TripCardMetrics.forHeight(size.height).alturaMaximaFactor;

      // Cabe entera bajo el techo => no scrollea.
      expect(
        alto,
        lessThanOrEqualTo(techo),
        reason: '$nombre: la tarjeta ($alto) supera su techo ($techo)',
      );

      // Y al mapa le queda más de la mitad de la pantalla.
      expect(
        size.height - alto,
        greaterThan(size.height * 0.5),
        reason: '$nombre: al mapa le quedan solo ${size.height - alto}',
      );
    });
  });

  testWidgets('con el código PIN visible la tarjeta crece pero sigue cabiendo', (
    tester,
  ) async {
    const size = Size(390, 844);
    final sinCodigo = await _alturaTarjeta(tester, pantalla: size);
    final conCodigo = await _alturaTarjeta(
      tester,
      pantalla: size,
      codigo: CodigoVerificacionEntity(
        codigo: '1234',
        generadoEn: DateTime(2026, 1, 1),
        validadoEn: null,
      ),
    );

    expect(conCodigo, greaterThan(sinCodigo));
    expect(
      conCodigo,
      lessThanOrEqualTo(size.height * TripCardMetrics.normal.alturaMaximaFactor),
    );
  });

  test('las medidas se eligen por franja de alto de pantalla', () {
    expect(TripCardMetrics.forHeight(640), same(TripCardMetrics.compacta));
    expect(TripCardMetrics.forHeight(844), same(TripCardMetrics.normal));
    expect(TripCardMetrics.forHeight(1280), same(TripCardMetrics.amplia));
  });
}
