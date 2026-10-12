import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/caracteristicas/anuncios/dominio/entidades/anuncio.dart';
import 'package:taxi_app/caracteristicas/anuncios/dominio/entidades/promocion.dart';
import 'package:taxi_app/caracteristicas/anuncios/dominio/repositorios/anuncios_repository.dart';
import 'package:taxi_app/caracteristicas/anuncios/dominio/enlaces_anuncio.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/vistas/admin_anuncios_screen.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/vistas/editor_anuncio_screen.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/widgets/detalle_anuncio.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/vistas/enviar_promocion_screen.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/vistas/promociones_admin_screen.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/widgets/carrusel_anuncios.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/widgets/oyente_promociones.dart';
import 'package:taxi_app/caracteristicas/anuncios/presentacion/widgets/ventana_promocion.dart';
import 'package:taxi_app/core/theme/app_theme.dart';

Promocion _promo(String id) => Promocion(
  id: id,
  titulo: 'Viaja con 20% menos',
  cuerpo: 'Este fin de semana todos los viajes tienen descuento.',
  imagenUrl: '',
  audiencia: AudienciaPromocion.todos,
  venceEn: null,
);

class _RepoFalso implements AnunciosRepository {
  _RepoFalso(this.anuncios);

  final List<Anuncio> anuncios;

  @override
  Stream<List<Anuncio>> watchAnuncios() => Stream.value(anuncios);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final vistas = <String>{};
  final eliminadas = <String>[];
  final anunciosEditados = <String, String>{};

  @override
  Future<void> actualizarAnuncio(
    Anuncio anuncio, {
    required String titulo,
    required String detalle,
    required String whatsapp,
    required String instagram,
    int? dias,
    Uint8List? nuevaImagen,
  }) async => anunciosEditados[anuncio.id] = '$titulo|$whatsapp|$dias';
  final editadas = <String, String>{};

  @override
  Future<void> eliminarPromocion(Promocion promo) async =>
      eliminadas.add(promo.id);

  @override
  Future<void> actualizarPromocion(
    Promocion promo, {
    required String titulo,
    required String cuerpo,
    required AudienciaPromocion audiencia,
    int? dias,
    Uint8List? nuevaImagen,
    bool quitarImagen = false,
  }) async => editadas[promo.id] = titulo;

  @override
  Future<Set<String>> promocionesVistas() async => {...vistas};

  @override
  Future<void> marcarPromocionVista(String id) async => vistas.add(id);

  @override
  Stream<List<Promocion>> watchPromociones({int limite = 50}) => Stream.value([
    _promo('p1'),
    Promocion(
      id: 'p2',
      titulo: 'Promo vencida con un título bastante largo para probar',
      cuerpo: 'Texto',
      imagenUrl: '',
      audiencia: AudienciaPromocion.conductores,
      venceEn: DateTime(2020),
      creadoEn: DateTime(2020),
    ),
  ]);

  @override
  Future<Promocion?> obtenerPromocion(String id) async =>
      id == 'p1' ? _promo('p1') : null;
}

void main() {
  final ahora = DateTime(2026, 10, 12, 12);

  test('un anuncio sin vencimiento siempre está vigente', () {
    final sinFin = Anuncio(id: 'a', imagenUrl: 'u', creadoEn: ahora);
    final vencido = Anuncio(
      id: 'b',
      imagenUrl: 'u',
      creadoEn: ahora,
      venceEn: ahora.subtract(const Duration(minutes: 1)),
    );
    expect(sinFin.vigente(ahora), isTrue);
    expect(vencido.vigente(ahora), isFalse);
  });

  testWidgets('el carrusel pasa solo cada 10 s y omite los vencidos', (
    tester,
  ) async {
    final repo = _RepoFalso([
      Anuncio(id: 'a', imagenUrl: 'https://x/a.jpg', creadoEn: DateTime.now()),
      Anuncio(
        id: 'vencido',
        imagenUrl: 'https://x/v.jpg',
        creadoEn: DateTime.now(),
        venceEn: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: CarruselAnuncios(
              tarjetaFinal: const Text('promociona'),
              repositorio: repo,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Primero el anuncio; "¿Quieres promocionar?" va al final.
    expect(find.text('promociona'), findsNothing);
    // 2 páginas (1 anuncio vigente + promociona) → 2 puntos.
    expect(find.byType(AnimatedContainer), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('promociona'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('promociona'), findsNothing, reason: 'vuelve al inicio');
  });

  for (final ancho in [320.0, 360.0, 1200.0]) {
    testWidgets('pantallas del admin sin desbordes a ${ancho.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _RepoFalso(const []);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppThemeConfig.lightTheme,
            // Letra grande de accesibilidad: el peor caso del selector.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: EnviarPromocionScreen(repositorio: repo),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Enviar promoción'), findsWidgets);
      final conductores = find.text('Conductores');
      expect(conductores, findsOneWidget);
      // Completo: ni cortado con "…" ni partido en dos líneas.
      final parrafo = tester.renderObject<RenderParagraph>(conductores);
      expect(parrafo.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppThemeConfig.lightTheme,
            home: AdminAnunciosScreen(repositorio: repo),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Aún no hay anuncios.'), findsOneWidget);
      expect(find.text('Publicados'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // La pestaña "Crear" tiene el editor con la vista previa.
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.text('Así se verá en el inicio'), findsOneWidget);
      expect(find.text('Publicar anuncio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final ancho in [320.0, 1200.0]) {
    testWidgets('ventana de promoción sin desbordes a ${ancho.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(ancho, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: VentanaPromocion(promo: _promo('p1'))),
      );
      expect(find.text('Viaja con 20% menos'), findsOneWidget);
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tocar la notificación abre la ventana y la X la cierra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fuente = ValueNotifier<String?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OyentePromociones(
            publico: AudienciaPromocion.clientes,
            // Ya vista: así solo la abre el tap, no la aparición sola.
            repositorio: _RepoFalso(const [])..vistas.add('p1'),
            fuente: fuente,
          ),
        ),
      ),
    );
    fuente.value = 'p1'; // lo que hace FcmService al tocar la notificación
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Viaja con 20% menos'), findsOneWidget);
    expect(fuente.value, isNull, reason: 'se consume una sola vez');

    await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: true);
    expect(
      tester.getRect(find.byTooltip('Cerrar')).bottom,
      lessThanOrEqualTo(844),
      reason: 'la X entra en un teléfono sin desplazar',
    );
    await tester.pumpAndSettle();
    expect(find.text('Viaja con 20% menos'), findsNothing);
  });

  for (final ancho in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'promociones: lista y detalle sin desbordes a ${ancho.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(ancho, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: AppThemeConfig.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: PromocionesAdminScreen(repositorio: _RepoFalso(const [])),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Viaja con 20% menos'), findsOneWidget);
        expect(find.text('Vencida'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Viaja con 20% menos'));
        await tester.pumpAndSettle();
        expect(find.text('Detalle de la promoción'), findsOneWidget);
        expect(find.text('Ver como la ven los usuarios'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('promocionParaMostrar', () {
    final ahora = DateTime(2026, 10, 12, 12);
    Promocion p(
      String id, {
      AudienciaPromocion a = AudienciaPromocion.todos,
      DateTime? vence,
    }) => Promocion(
      id: id,
      titulo: id,
      cuerpo: '',
      imagenUrl: '',
      audiencia: a,
      venceEn: vence,
    );

    test('la más nueva para el público, vigente y sin ver', () {
      final elegida = promocionParaMostrar(
        [
          p('vencida', vence: ahora.subtract(const Duration(hours: 1))),
          p('de-conductores', a: AudienciaPromocion.conductores),
          p('vista'),
          p('esta', a: AudienciaPromocion.clientes),
          p('vieja'),
        ],
        publico: AudienciaPromocion.clientes,
        vistas: {'vista'},
        ahora: ahora,
      );
      expect(elegida?.id, 'esta');
    });

    test('"Todos" también le sale al conductor; nada si ya la vio', () {
      final lista = [p('a')];
      expect(
        promocionParaMostrar(
          lista,
          publico: AudienciaPromocion.conductores,
          vistas: const {},
          ahora: ahora,
        )?.id,
        'a',
      );
      expect(
        promocionParaMostrar(
          lista,
          publico: AudienciaPromocion.conductores,
          vistas: {'a'},
          ahora: ahora,
        ),
        isNull,
      );
    });
  });

  testWidgets('sale sola en el inicio una sola vez, sin tocar nada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RepoFalso(const []);
    Widget inicio() => MaterialApp(
      home: Scaffold(
        body: OyentePromociones(
          publico: AudienciaPromocion.clientes,
          repositorio: repo,
          fuente: ValueNotifier<String?>(null),
        ),
      ),
    );

    await tester.pumpWidget(inicio());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Viaja con 20% menos'), findsOneWidget);
    expect(repo.vistas, contains('p1'));

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    // Volver a entrar al inicio: ya no se repite (la otra está vencida).
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(inicio());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Viaja con 20% menos'), findsNothing);
  });

  Widget conTema(Widget home) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) =>
        MaterialApp(theme: AppThemeConfig.lightTheme, home: home),
  );

  testWidgets('desde el detalle se elimina con confirmación', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RepoFalso(const []);
    await tester.pumpWidget(
      conTema(DetallePromocionScreen(_promo('p1'), repositorio: repo)),
    );
    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();
    expect(repo.eliminadas, ['p1']);
  });

  testWidgets('editar abre el formulario lleno y guarda los cambios', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RepoFalso(const []);
    await tester.pumpWidget(
      conTema(DetallePromocionScreen(_promo('p1'), repositorio: repo)),
    );
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar promoción'), findsOneWidget);
    expect(find.text('Viaja con 20% menos'), findsOneWidget);
    expect(find.text('Mantener'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Nuevo título');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repo.editadas['p1'], 'Nuevo título');
    expect(find.text('Detalle de la promoción'), findsOneWidget);
  });

  group('enlaces del anuncio', () {
    test('WhatsApp: celular colombiano recibe el 57; con indicativo queda', () {
      expect(
        enlaceWhatsApp('300 123-4567').toString(),
        'https://wa.me/573001234567',
      );
      expect(
        enlaceWhatsApp('+57 300 1234567', mensaje: 'Hola').toString(),
        'https://wa.me/573001234567?text=Hola',
      );
      expect(enlaceWhatsApp('123'), isNull);
    });

    test('Instagram: @usuario, usuario o enlace', () {
      const esperado = 'https://www.instagram.com/mi.negocio_1/';
      expect(enlaceInstagram('@mi.negocio_1').toString(), esperado);
      expect(enlaceInstagram('mi.negocio_1').toString(), esperado);
      expect(
        enlaceInstagram('https://instagram.com/mi.negocio_1?igsh=x').toString(),
        esperado,
      );
      expect(enlaceInstagram('no válido!'), isNull);
    });
  });

  final anuncioCompleto = Anuncio(
    id: 'a1',
    imagenUrl: 'https://x/a.jpg',
    creadoEn: DateTime(2026),
    titulo: 'Panadería La Espiga',
    detalle: 'Pan caliente todo el día. Domicilios en Ocaña.',
    whatsapp: '3001234567',
    instagram: '@laespiga',
  );

  testWidgets('el editor pide la imagen y valida el WhatsApp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      conTema(EditorAnuncioScreen(repositorio: _RepoFalso(const []))),
    );
    expect(find.text('Así se verá en el inicio'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'WhatsApp'), '12');
    await tester.pump();
    expect(find.text('Número no válido (ej. 300 123 4567).'), findsOneWidget);

    await tester.ensureVisible(find.text('Publicar anuncio'));
    await tester.tap(find.text('Publicar anuncio'));
    await tester.pump();
    expect(find.text('Elige la imagen del anuncio.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editar un anuncio guarda sin tocar la imagen ni la duración', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RepoFalso(const []);
    await tester.pumpWidget(
      conTema(
        EditorAnuncioScreen(editando: anuncioCompleto, repositorio: repo),
      ),
    );
    expect(find.text('Panadería La Espiga'), findsOneWidget);
    expect(find.text('Mantener'), findsOneWidget);
    expect(find.text('Ver detalle'), findsOneWidget, reason: 'vista previa');

    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repo.anunciosEditados['a1'], 'Panadería La Espiga|3001234567|null');
  });

  testWidgets('detalle del anuncio con WhatsApp e Instagram a 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      conTema(Scaffold(body: DetalleAnuncio(anuncio: anuncioCompleto))),
    );
    expect(find.text('Escribir por WhatsApp'), findsOneWidget);
    expect(find.text('Ver en Instagram'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin enlaces válidos no muestra botones de contacto', (
    tester,
  ) async {
    await tester.pumpWidget(
      conTema(
        Scaffold(
          body: DetalleAnuncio(
            anuncio: Anuncio(
              id: 'b',
              imagenUrl: 'https://x/b.jpg',
              creadoEn: DateTime(2026),
              titulo: 'Solo título',
              whatsapp: '12',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Solo título'), findsOneWidget);
    expect(find.text('Escribir por WhatsApp'), findsNothing);
  });
}
