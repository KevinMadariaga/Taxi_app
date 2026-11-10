import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/disponibilidad_conductores/dominio/conductores_presentes_repository.dart';
import 'package:taxi_app/caracteristicas/disponibilidad_conductores/dominio/disponibilidad_conductores.dart';
import 'package:taxi_app/caracteristicas/disponibilidad_conductores/presentacion/aviso_disponibilidad_en_vivo.dart';
import 'package:taxi_app/caracteristicas/viaje_pendiente/dominio/programacion_viaje.dart';
import 'package:taxi_app/caracteristicas/viaje_pendiente/dominio/viaje_pendiente.dart';
import 'package:taxi_app/caracteristicas/viaje_pendiente/dominio/viaje_pendiente_repository.dart';
import 'package:taxi_app/caracteristicas/viaje_pendiente/presentacion/banner_viaje_pendiente.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

const _lat = 8.2375;
const _lng = -73.3560;
final _ahora = DateTime(2026, 11, 7, 12);

ConductorPresente _c({
  double lat = _lat,
  bool moto = false,
  Duration hace = Duration.zero,
}) => ConductorPresente(
  lat: lat,
  lng: _lng,
  esMoto: moto,
  visto: _ahora.subtract(hace),
);

DisponibilidadConductores _d(List<ConductorPresente> lista) =>
    calcularDisponibilidad(lista, lat: _lat, lng: _lng, ahora: _ahora);

class _Presentes implements ConductoresPresentesRepository {
  _Presentes(this.lista);
  final List<ConductorPresente> lista;
  @override
  Stream<List<ConductorPresente>> watch() => Stream.value(lista);
}

class _Pendientes implements ViajePendienteRepository {
  _Pendientes(this.lista);
  final List<ViajePendiente> lista;
  final cancelados = <String>[];
  @override
  Stream<List<ViajePendiente>> watch(String clienteId) => Stream.value(lista);
  @override
  Future<void> cancelar(String id) async => cancelados.add(id);
}

Widget _app(Widget hijo) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: AppThemeConfig.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: hijo)),
  ),
);

void main() {
  group('disponibilidad', () {
    test('cuenta por tipo solo a los frescos y dentro de 3 km', () {
      final d = _d([
        _c(),
        _c(moto: true),
        _c(moto: true),
        _c(hace: const Duration(minutes: 6)), // se fue
        _c(lat: _lat + 0.05), // ~5.5 km
      ]);
      expect(d.carros, 1);
      expect(d.motos, 2);
    });

    test('guarda la distancia del más cercano de cada tipo', () {
      final d = _d([_c(lat: _lat + 0.01), _c()]);
      expect(d.metrosCarroMasCercano, closeTo(0, 1));
      expect(d.metrosMotoMasCercana, isNull);
    });
  });

  group('aviso antes de pedir', () {
    AvisoDisponibilidad? aviso(int carros, int motos, {bool moto = false}) =>
        avisoDisponibilidad(
          DisponibilidadConductores(carros: carros, motos: motos),
          esMoto: moto,
        );

    test('con conductores de sobra no molesta', () {
      expect(aviso(3, 0), isNull);
    });

    test('con pocos advierte la espera, sin ofrecer cambio', () {
      final a = aviso(2, 5)!;
      expect(a.mensaje, contains('Pocos conductores'));
      expect(a.ofrecerMoto, isNull);
    });

    test('sin carros pero con motos ofrece moto', () {
      final a = aviso(0, 2)!;
      expect(a.mensaje, contains('2 motos'));
      expect(a.ofrecerMoto, isTrue);
    });

    test('y al revés: sin motos pero con carros ofrece carro', () {
      expect(aviso(1, 0, moto: true)!.ofrecerMoto, isFalse);
    });

    test('sin nadie lo dice, sin nada a qué cambiar', () {
      final a = aviso(0, 0)!;
      expect(a.critico, isTrue);
      expect(a.ofrecerMoto, isNull);
    });
  });

  group('progreso de la búsqueda', () {
    test('sigue el reparto y lo que los conductores hacen', () {
      String t(int? n, int v) =>
          textoProgresoBusqueda(notificados: n, vistas: v);
      expect(t(null, 0), 'Notificando a conductores cercanos…');
      expect(t(0, 0), contains('Aún no hay conductores'));
      expect(t(4, 0), 'Avisamos a 4 conductores cercanos');
      expect(t(4, 1), '1 conductor vio tu solicitud');
      expect(t(4, 3), '3 conductores vieron tu solicitud');
    });

    test('el tiempo estimado es un rango, y nada si no hay a quién medir', () {
      expect(textoTiempoEstimado(null), isNull);
      // 800 m a 25 km/h ≈ 2 min, +1 de aceptar.
      expect(textoTiempoEstimado(800), '3–5 min');
    });
  });

  group('programar viaje', () {
    test('respeta el mínimo de 30 min y salta de 15 en 15', () {
      final horarios = horariosProgramables(
        DateTime(2026, 11, 7),
        DateTime(2026, 11, 7, 12, 5),
      );
      expect(horarios.first, DateTime(2026, 11, 7, 12, 45));
      expect(horarios[1], DateTime(2026, 11, 7, 13));
    });

    test('tarde en la noche "hoy" no se ofrece', () {
      final ahora = DateTime(2026, 11, 7, 23, 50);
      expect(diasProgramables(ahora).first, DateTime(2026, 11, 8));
    });

    test('no deja programar más allá de 7 días', () {
      final ahora = DateTime(2026, 11, 7, 12);
      final dias = diasProgramables(ahora);
      expect(dias.last, DateTime(2026, 11, 14));
      expect(
        horariosProgramables(dias.last, ahora).last,
        DateTime(2026, 11, 14, 12),
      );
    });

    test('texto de la fecha', () {
      final ahora = DateTime(2026, 11, 7, 12);
      expect(
        textoFechaProgramada(DateTime(2026, 11, 7, 15, 30), ahora),
        'Hoy, 3:30 p. m.',
      );
      expect(
        textoFechaProgramada(DateTime(2026, 11, 8, 0, 15), ahora),
        'Mañana, 12:15 a. m.',
      );
      expect(textoDia(DateTime(2026, 11, 10), ahora), 'mar 10 nov');
    });
  });

  group('qué muestra el inicio', () {
    test('solo lo que anda sin una pantalla abierta', () {
      expect(
        ViajePendiente.tipoDe('programada', true),
        TipoViajePendiente.programado,
      );
      expect(
        ViajePendiente.tipoDe('buscando', true),
        TipoViajePendiente.buscandoConAviso,
      );
      expect(
        ViajePendiente.tipoDe('asignado', true),
        TipoViajePendiente.conductorEncontrado,
      );
      expect(ViajePendiente.tipoDe('buscando', false), isNull);
      expect(ViajePendiente.tipoDe('asignado', false), isNull);
    });
  });

  for (final ancho in [320.0, 390.0]) {
    testWidgets('aviso en vivo: cambia a moto de un toque a ${ancho.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? elegido;
      await tester.pumpWidget(
        _app(
          AvisoDisponibilidadEnVivo(
            lat: _lat,
            lng: _lng,
            esMoto: false,
            repositorio: _Presentes([
              ConductorPresente(
                lat: _lat,
                lng: _lng,
                esMoto: true,
                visto: DateTime.now(),
              ),
            ]),
            onCambiarVehiculo: (moto) => elegido = moto,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('No hay carros cerca'), findsOneWidget);
      await tester.tap(find.text('Pedir moto'));
      expect(elegido, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mientras carga no dice que no hay conductores', (tester) async {
    await tester.pumpWidget(
      _app(
        AvisoDisponibilidadEnVivo(
          lat: _lat,
          lng: _lng,
          esMoto: false,
          repositorio: _SinDatos(),
          onCambiarVehiculo: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('el banner muestra el programado y lo cancela con confirmación', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Pendientes([
      ViajePendiente(
        id: 'p1',
        tipo: TipoViajePendiente.programado,
        destino: 'Parque principal de Ocaña',
        programadaPara: DateTime.now().add(const Duration(hours: 2)),
      ),
    ]);
    await tester.pumpWidget(
      _app(BannerViajePendiente(repositorio: repo, clienteId: 'c1')),
    );
    await tester.pump();
    expect(find.textContaining('Viaje programado'), findsOneWidget);
    expect(find.text('Parque principal de Ocaña'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Cancelar viaje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar viaje').last);
    await tester.pumpAndSettle();
    expect(repo.cancelados, ['p1']);
  });

  group('el conductor acepta con algo encima del inicio', () {
    const encontrado = ViajePendiente(
      id: 'v1',
      tipo: TipoViajePendiente.conductorEncontrado,
      destino: 'Parque',
    );

    Future<void> probar(
      WidgetTester tester,
      void Function(BuildContext) taparInicio,
    ) async {
      final viajes = StreamController<List<ViajePendiente>>();
      addTearDown(viajes.close);
      final abiertos = <String>[];
      await tester.pumpWidget(
        _app(
          BannerViajePendiente(
            repositorio: _PendientesEnVivo(viajes.stream),
            clienteId: 'c1',
            abrirViaje: abiertos.add,
          ),
        ),
      );
      final inicio = tester.element(find.byType(BannerViajePendiente));

      taparInicio(inicio);
      await tester.pumpAndSettle();
      viajes.add(const [encontrado]);
      await tester.pumpAndSettle();
      expect(abiertos, isEmpty, reason: 'con algo encima no navega');

      Navigator.of(inicio).pop();
      await tester.pumpAndSettle();
      expect(abiertos, ['v1'], reason: 'se abre al volver al inicio');

      // Otra vuelta al inicio no lo abre de nuevo.
      taparInicio(inicio);
      await tester.pumpAndSettle();
      Navigator.of(inicio).pop();
      await tester.pumpAndSettle();
      expect(abiertos, ['v1']);
      expect(tester.takeException(), isNull);
    }

    testWidgets('una hoja (la campana)', (tester) async {
      await probar(tester, (c) {
        showModalBottomSheet<void>(
          context: c,
          builder: (_) => const SizedBox(height: 100),
        );
      });
    });

    testWidgets('otra pantalla', (tester) async {
      await probar(tester, (c) {
        Navigator.of(
          c,
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      });
    });
  });
}

class _PendientesEnVivo implements ViajePendienteRepository {
  _PendientesEnVivo(this.viajes);
  final Stream<List<ViajePendiente>> viajes;
  @override
  Stream<List<ViajePendiente>> watch(String clienteId) => viajes;
  @override
  Future<void> cancelar(String id) async {}
}

class _SinDatos implements ConductoresPresentesRepository {
  @override
  Stream<List<ConductorPresente>> watch() => const Stream.empty();
}
