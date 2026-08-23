import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/participante_viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/entidades/viaje_entity.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/repositorios/viaje_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/actualizar_estado_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/dominio/casos_uso/watch_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/controladores/chat_controller.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/presentacion/utils/trip_card_metrics.dart';
import 'package:taxi_app/caracteristicas/viaje_compartido/datos/fuentes/ruta_datasource.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/generar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/casos_uso/validar_codigo_verificacion_usecase.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/entidades/codigo_verificacion_entity.dart';
import 'package:taxi_app/caracteristicas/verificacion_recogida/dominio/repositorios/codigo_verificacion_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/driver_ubicacion_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/datos/fuentes/navegacion_externa_datasource.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/finalizar_viaje_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/iniciar_ruta_destino_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/dominio/casos_uso/reportar_llegada_usecase.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/viewmodels/viaje_conductor_viewmodel.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/driver_trip_card.dart';
import 'package:taxi_app/caracteristicas/viaje_conductor/presentacion/widgets/driver_trip_card/widgets/acciones_conductor_buttons.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';

import 'test_helpers/firebase_test_setup.dart';

/// Regresión del hueco vacío que quedaba entre el botón "Terminar viaje" y
/// el mapa en la card del conductor: antes `ConstrainedBox(minHeight:)`
/// estiraba la card a toda la mitad de `InfoMapSplit` aunque su contenido
/// fuera más corto (ver `viaje_conductor_screen.dart`). Ahora la card mide
/// su contenido, igual que `TripInfoCard` del lado cliente
/// (`test/trip_info_card_altura_test.dart`, mismo set de pantallas).
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
}

class _FakeCodigoRepository implements CodigoVerificacionRepository {
  @override
  Future<CodigoVerificacionEntity?> obtenerCodigo(String viajeId) async =>
      null;

  @override
  Stream<CodigoVerificacionEntity?> watchCodigo(String viajeId) =>
      const Stream.empty();

  @override
  Future<void> guardarCodigo(
    String viajeId,
    CodigoVerificacionEntity codigo,
  ) async {}

  @override
  Future<void> marcarValidado(String viajeId) async {}

  @override
  Future<void> incrementarIntentoFallido(String viajeId) async {}
}

const _cliente = ParticipanteViajeEntity(
  id: 'u1',
  nombre: 'Ana',
  fotoUrl: '',
  fotoVehiculoUrl: '',
  placaVehiculo: '',
  calificacion: 5,
  totalCalificaciones: 3,
  direccion: 'Calle destino 123',
  ubicacion: LatLng(4.61, -74.07),
);

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

ViajeConductorViewModel _buildVm() {
  final viajeRepo = _FakeViajeRepository();
  final codigoRepo = _FakeCodigoRepository();
  final actualizar = ActualizarEstadoViajeUseCase(viajeRepo);
  final vm = ViajeConductorViewModel(
    viajeId: 'v1',
    conductorId: 'c1',
    watchViaje: WatchViajeUseCase(viajeRepo),
    actualizarEstado: actualizar,
    reportarLlegada: ReportarLlegadaUseCase(
      actualizarEstado: actualizar,
      generarCodigo: GenerarCodigoVerificacionUseCase(codigoRepo),
    ),
    iniciarRutaDestino: IniciarRutaDestinoUseCase(
      actualizarEstado: actualizar,
      validarCodigo: ValidarCodigoVerificacionUseCase(codigoRepo),
    ),
    finalizarViaje: FinalizarViajeUseCase(actualizar),
    ubicacionDatasource: DriverUbicacionDatasource(),
    rutaDatasource: RutaDatasource(),
    navegacionDatasource: NavegacionExternaDatasource(),
    chatController: ChatController(
      viajeId: 'v1',
      currentUserId: 'c1',
      otherPartyLabel: 'cliente',
    ),
  );
  vm.viaje = ViajeEntity(
    id: 'v1',
    // "Llévalo a su destino": el estado del enunciado.
    estado: SolicitudEstado.enRuta,
    cliente: _cliente,
    conductor: _conductor,
    destino: const DestinoViajeEntity(
      direccion: 'Destino',
      ubicacion: LatLng(4.65, -74.05),
    ),
    updatedAt: DateTime(2026, 1, 1),
  );
  return vm;
}

/// Renderiza la card igual que `ViajeConductorScreen`:
/// `ConstrainedBox(maxHeight:)` + `SingleChildScrollView`, y devuelve tanto
/// el alto real de la card como el hueco entre el botón primario y el
/// borde inferior de la card.
Future<({double alturaCard, double huecoBajoBoton})> _medir(
  WidgetTester tester, {
  required Size pantalla,
}) async {
  tester.view.physicalSize = pantalla;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
                child: DriverTripCard(
                  vm: vm,
                  onChat: () {},
                  onDetails: () {},
                  onReportarLlegada: () {},
                  onComenzarRuta: () {},
                  onTerminarViaje: () {},
                ),
              ),
            ),
            const Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ),
  );

  final cardRect = tester.getRect(find.byType(DriverTripCard));
  final botonesRect = tester.getRect(find.byType(AccionesConductorButtons));

  return (
    alturaCard: cardRect.height,
    huecoBajoBoton: cardRect.bottom - botonesRect.bottom,
  );
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
    testWidgets(
      '$nombre: sin hueco muerto bajo "Terminar viaje" y la card cabe bajo su techo',
      (tester) async {
        final medida = await _medir(tester, pantalla: size);
        final techo =
            size.height * TripCardMetrics.forHeight(size.height).alturaMaximaFactor;

        // Cabe entera bajo el techo — antes `ConstrainedBox(minHeight:)` la
        // estiraba a toda la mitad de `InfoMapSplit` sin importar su
        // contenido.
        expect(
          medida.alturaCard,
          lessThanOrEqualTo(techo),
          reason: '$nombre: la card (${medida.alturaCard}) supera su techo ($techo)',
        );

        // El hueco entre "Terminar viaje" y el borde inferior de la card es
        // solo el padding vertical de `TripCardMetrics` — no una franja
        // vacía forzada por el flex de la pantalla.
        expect(
          medida.huecoBajoBoton,
          lessThan(40),
          reason:
              '$nombre: queda un hueco de ${medida.huecoBajoBoton}px bajo el botón primario',
        );
      },
    );
  });
}
