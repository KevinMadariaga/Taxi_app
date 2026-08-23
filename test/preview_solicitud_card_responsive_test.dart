// Matriz de responsividad de `PreviewSolicitudCard` — para cada tamaño de
// pantalla/inset físico simulado, verifica que no haya overflow de layout
// Y que "Aceptar" quede visible sin necesidad de scroll. Cubre: Android con
// barra de navegación de 3 botones, Android con gesture nav (inset físico
// en 0), iOS con home indicator, iOS con botón físico (sin inset), pantalla
// chica, pantalla grande/tablet y la más alta de las "normales" (Pro Max) —
// cruzado con presencia de comentario del cliente y de contraoferta, que
// son las dos variables que más cambian la altura real del panel de info.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/data/models/solicitud_item.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';
import 'package:taxi_app/widgets/preview_solicitud/preview_solicitud_card.dart';
import 'package:taxi_app/widgets/preview_solicitud/widgets/acciones_solicitud_buttons.dart';
import 'package:taxi_app/widgets/preview_solicitud/widgets/mapa_previsualizacion_solicitud.dart';

import 'test_helpers/firebase_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupFirebaseForTests();
  });

  PreviewSolicitud buildPreview({
    required bool comentario,
    required bool contraoferta,
  }) {
    return PreviewSolicitud(
      SolicitudItem(
        id: 'sol-1',
        clienteId: 'cli-1',
        ubicacionInicial: const GeoPoint(10.5, -66.9),
        nombreCliente: 'Juan Pérez',
        comentarioCliente: comentario
            ? 'Por favor tocar la bocina al llegar'
            : null,
        direccion: 'Av. Principal con calle 5, Caracas',
        valorServicio: 5.0,
        valorContraoferta: contraoferta ? 6.0 : null,
        metodoPago: 'Efectivo',
        distanciaKm: 1.2,
      ),
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required Size size,
    required double viewPaddingBottom,
    required double statusBarTop,
    required double paddingBottom,
    bool comentario = true,
    bool contraoferta = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = FakeViewPadding(
      top: statusBarTop,
      bottom: viewPaddingBottom,
      left: 0,
      right: 0,
    );
    tester.view.padding = FakeViewPadding(
      top: statusBarTop,
      bottom: paddingBottom,
      left: 0,
      right: 0,
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: PreviewSolicitudCard(
            preview: buildPreview(
              comentario: comentario,
              contraoferta: contraoferta,
            ),
            driverLocation: const LatLng(10.51, -66.91),
            onClose: () {},
            onAccept: () {},
            onCounterOffer: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  final escenarios =
      <
        String,
        ({
          Size size,
          double viewPaddingBottom,
          double statusBarTop,
          double paddingBottom,
        })
      >{
        // Android con barra de navegación física de 3 botones.
        'Android barra 3 botones (Pixel 6a)': (
          size: const Size(412, 892),
          viewPaddingBottom: 48,
          statusBarTop: 31,
          paddingBottom: 0, // Scaffold body ya está bajo el SafeArea ancestro
        ),
        // Android gesture nav completo: inset físico en 0.
        'Android gesture nav (inset 0)': (
          size: const Size(412, 892),
          viewPaddingBottom: 0,
          statusBarTop: 31,
          paddingBottom: 0,
        ),
        // iPhone con Face ID / home indicator (todos desde iPhone X).
        'iOS home indicator (iPhone 14)': (
          size: const Size(390, 844),
          viewPaddingBottom: 34,
          statusBarTop: 47,
          paddingBottom: 0,
        ),
        // iPhone con botón físico (SE) — sin inset inferior.
        'iOS botón físico (iPhone SE)': (
          size: const Size(375, 667),
          viewPaddingBottom: 0,
          statusBarTop: 20,
          paddingBottom: 0,
        ),
        // Pantalla chica real (Android gama baja).
        'Android chico (320x568)': (
          size: const Size(320, 568),
          viewPaddingBottom: 0,
          statusBarTop: 24,
          paddingBottom: 0,
        ),
        // Pantalla grande / tablet.
        'Tablet grande (800x1280)': (
          size: const Size(800, 1280),
          viewPaddingBottom: 0,
          statusBarTop: 24,
          paddingBottom: 0,
        ),
        // iPhone Pro Max, la más alta de las "normales".
        'iOS Pro Max (iPhone 15 Pro Max)': (
          size: const Size(430, 932),
          viewPaddingBottom: 34,
          statusBarTop: 59,
          paddingBottom: 0,
        ),
      };

  for (final entry in escenarios.entries) {
    for (final comentario in [false, true]) {
      for (final contraoferta in [false, true]) {
        final desc =
            '${entry.key} — comentario=$comentario contraoferta=$contraoferta';
        testWidgets(desc, (tester) async {
          await pumpCard(
            tester,
            size: entry.value.size,
            viewPaddingBottom: entry.value.viewPaddingBottom,
            statusBarTop: entry.value.statusBarTop,
            paddingBottom: entry.value.paddingBottom,
            comentario: comentario,
            contraoferta: contraoferta,
          );
          expect(tester.takeException(), isNull, reason: desc);

          // El botón "Aceptar" tiene que quedar completamente visible por
          // encima del inset físico (barra de navegación / home indicator)
          // — si `navBarGap` se queda corto, el botón termina tapado.
          final boton = find.byType(AccionesSolicitudButtons);
          expect(boton, findsOneWidget, reason: desc);
          final rect = tester.getRect(boton);
          final screenHeight = entry.value.size.height;
          final insetInferior = entry.value.viewPaddingBottom;
          expect(
            rect.bottom,
            lessThanOrEqualTo(screenHeight - insetInferior),
            reason: '$desc — "Aceptar" tapado por el inset físico',
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(0),
            reason: '$desc — "Aceptar" fuera de pantalla por arriba',
          );

          // Regresión: con un split por flex (fijo o adaptado por
          // contenido), el aire sobrante de pantallas altas/tablets se
          // acumulaba DEBAJO de "Aceptar" además del `navBarGap`, dejando
          // un hueco grande entre el botón y el borde de la pantalla. 120px
          // cubre holgadamente el `navBarGap` más alto del set (barra de 3
          // botones de Android, escalado por ScreenUtil en pantallas
          // grandes) sin dejar pasar ese sobrante.
          final huecoInferior = screenHeight - insetInferior - rect.bottom;
          expect(
            huecoInferior,
            lessThan(120),
            reason:
                '$desc — hueco de ${huecoInferior.toStringAsFixed(1)}px '
                'entre "Aceptar" y el borde inferior, mucho más que el '
                'navBarGap esperado',
          );

          // Regresión: con un split por flex, el mapa podía terminar antes
          // de lo que su contenido necesitaba, dejando un hueco en blanco
          // entre el mapa y la tarjeta de cliente — el mapa ahora es
          // `Expanded` (se queda con lo que el panel de info no usa), así
          // que ese hueco debería ser solo el padding superior del panel
          // (12.h ScreenUtil ≈ 12-18px reales según el tamaño de pantalla).
          final mapaBottom = tester
              .getRect(find.byType(MapaPrevisualizacionSolicitud))
              .bottom;
          final cardTop = tester
              .getRect(find.byKey(const Key('preview_solicitud_cliente_card')))
              .top;
          final huecoMapaCard = cardTop - mapaBottom;
          expect(
            huecoMapaCard,
            inClosedOpenRange(0, 40),
            reason:
                '$desc — hueco de ${huecoMapaCard.toStringAsFixed(1)}px '
                'entre el mapa y la tarjeta de cliente',
          );
        });
      }
    }
  }
}
