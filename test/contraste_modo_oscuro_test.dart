import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/core/theme/ride_button_styles.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Contraste WCAG 2.x entre dos colores opacos.
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

/// AA para texto normal. Los íconos (3:1) quedan cubiertos con margen.
const aa = 4.5;

void main() {
  const oscuro = AppPalette.dark;

  test('colores de estado legibles sobre las superficies oscuras', () {
    final tokens = {
      'successText': oscuro.successText,
      'errorText': oscuro.errorText,
      'dangerText': oscuro.dangerText,
      'infoText': oscuro.infoText,
    };
    for (final fondo in [oscuro.cardBackground, oscuro.surface]) {
      tokens.forEach((nombre, color) {
        expect(
          contraste(color, fondo),
          greaterThanOrEqualTo(aa),
          reason: '$nombre sobre $fondo',
        );
      });
    }
  });

  test('chip de marca legible en ambos temas', () {
    for (final p in [AppPalette.light, oscuro]) {
      expect(
        contraste(p.brandChipText, p.brandChipBackground),
        greaterThanOrEqualTo(aa),
      );
    }
  });

  test('modo claro no cambia: los tokens nuevos son los de AppColores', () {
    const claro = AppPalette.light;
    expect(claro.successText, AppColores.success);
    expect(claro.errorText, AppColores.error);
    expect(claro.dangerText, AppColores.danger);
    expect(claro.infoText, AppColores.secondary);
    expect(claro.brandChipBackground, AppColores.brand50);
    expect(claro.brandChipText, AppColores.brand900);
  });

  test('sobre el ámbar el contenido es oscuro; sobre brand700, blanco', () {
    for (final ambar in [AppColores.primary, AppColores.brand400]) {
      expect(contraste(AppColores.ink900, ambar), greaterThanOrEqualTo(aa));
      // Por qué no blanco: queda muy por debajo.
      expect(contraste(Colors.white, ambar), lessThan(3));
    }
    expect(
      contraste(Colors.white, AppColores.brand700),
      greaterThanOrEqualTo(aa),
    );
  });

  group('RidePrimaryButton: color del texto', () {
    Future<Color?> colorTexto(
      WidgetTester tester, {
      required AppPalette palette,
      VoidCallback? onPressed,
      bool pastel = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [palette]),
          home: Scaffold(
            body: RidePrimaryButton(
              text: 'Ya llegué',
              onPressed: onPressed,
              pastel: pastel,
            ),
          ),
        ),
      );
      // MaterialApp anima el cambio de tema entre llamadas: esperar al final.
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text('Ya llegué')).style?.color;
    }

    testWidgets('deshabilitado usa ink500, no blanco sobre gris', (
      tester,
    ) async {
      for (final p in [AppPalette.light, oscuro]) {
        final color = await colorTexto(tester, palette: p);
        expect(color, p.ink500);
        expect(contraste(color!, p.ink200), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('pastel (ámbar) lleva texto oscuro; sólido, blanco', (
      tester,
    ) async {
      expect(
        await colorTexto(
          tester,
          palette: oscuro,
          onPressed: () {},
          pastel: true,
        ),
        AppColores.ink900,
      );
      expect(
        await colorTexto(tester, palette: oscuro, onPressed: () {}),
        AppColores.textWhite,
      );
    });
  });

  group('flecha "atrás" de la AppBar se adapta a cada tema', () {
    Future<Color?> colorFlecha(
      WidgetTester tester,
      ThemeData Function() tema,
      PreferredSizeWidget Function(BuildContext) appBar,
    ) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: tema(),
            home: Builder(
              builder: (context) => Scaffold(appBar: appBar(context)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<RichText>(
            find.descendant(
              of: find.byIcon(Icons.arrow_back_rounded),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
    }

    const flecha = Icon(Icons.arrow_back_rounded);

    for (final (nombre, tema, palette) in [
      ('claro', () => AppThemeConfig.lightTheme, AppPalette.light),
      ('oscuro', () => AppThemeConfig.darkTheme, AppPalette.dark),
    ]) {
      testWidgets('appBarNeutra en $nombre: flecha legible sobre el fondo', (
        tester,
      ) async {
        final color = await colorFlecha(
          tester,
          tema,
          (context) => appBarNeutra(
            context,
            titulo: 'Detalle',
            leading: IconButton(onPressed: () {}, icon: flecha),
          ),
        );
        expect(color, palette.textPrimary);
        expect(contraste(color!, palette.background), greaterThanOrEqualTo(aa));
      });
    }

    testWidgets('AppBar de marca (ámbar) lleva la flecha oscura', (
      tester,
    ) async {
      final color = await colorFlecha(
        tester,
        () => AppThemeConfig.lightTheme,
        (_) => AppBar(
          leading: IconButton(onPressed: () {}, icon: flecha),
        ),
      );
      expect(color, AppColores.ink900);
      expect(contraste(color!, AppColores.primary), greaterThanOrEqualTo(aa));
    });
  });

  test('colorContenidoSobre: oscuro sobre ámbar y grises claros', () {
    expect(colorContenidoSobre(AppColores.primary), AppColores.ink900);
    expect(colorContenidoSobre(AppPalette.light.grey400), AppColores.ink900);
    for (final fondo in [
      AppColores.success,
      AppColores.error,
      AppColores.brand700,
      AppPalette.dark.grey400,
    ]) {
      final c = colorContenidoSobre(fondo);
      expect(c, AppColores.textWhite, reason: '$fondo');
      expect(contraste(c, fondo), greaterThanOrEqualTo(aa));
    }
  });

  group('CustomButton: texto legible según el fondo', () {
    Future<Color?> colorTexto(
      WidgetTester tester, {
      ThemeData? tema,
      VoidCallback? onPressed,
      Color? color,
      Color? textColor,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tema ?? ThemeData(extensions: const [AppPalette.light]),
          home: Scaffold(
            body: CustomButton(
              text: 'Guardar cambios',
              onPressed: onPressed,
              color: color,
              textColor: textColor,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<Text>(find.text('Guardar cambios')).style?.color;
    }

    testWidgets('ámbar por defecto → oscuro; verde → blanco', (tester) async {
      expect(await colorTexto(tester, onPressed: () {}), AppColores.ink900);
      expect(
        await colorTexto(tester, onPressed: () {}, color: AppColores.success),
        AppColores.textWhite,
      );
    });

    testWidgets('deshabilitado legible en claro y en oscuro', (tester) async {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final color = await colorTexto(
          tester,
          tema: ThemeData(extensions: [p]),
        );
        expect(contraste(color!, p.grey400), greaterThanOrEqualTo(aa));
        // Aunque el llamador pase `textColor` blanco (pensado para su fondo
        // habilitado), deshabilitado el fondo es gris y manda el fondo.
        final conTextColor = await colorTexto(
          tester,
          tema: ThemeData(extensions: [p]),
          textColor: AppColores.textWhite,
        );
        expect(contraste(conTextColor!, p.grey400), greaterThanOrEqualTo(aa));
      }
    });
  });

  group('defaults del tema sobre el ámbar', () {
    for (final (nombre, tema, palette) in [
      ('claro', () => AppThemeConfig.lightTheme, AppPalette.light),
      ('oscuro', () => AppThemeConfig.darkTheme, AppPalette.dark),
    ]) {
      testWidgets(
        '$nombre: ElevatedButton/onPrimary oscuros, labelLarge del tema',
        (tester) async {
          late ThemeData t;
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) {
                t = tema();
                return const SizedBox();
              },
            ),
          );
          final fg = t.elevatedButtonTheme.style!.foregroundColor!.resolve({});
          expect(fg, AppColores.ink900);
          expect(t.colorScheme.onPrimary, AppColores.ink900);
          expect(t.appBarTheme.foregroundColor, AppColores.ink900);
          expect(t.textTheme.labelLarge!.color, palette.textPrimary);
        },
      );
    }
  });

  testWidgets('acentoMarca: ámbar legible como ícono/texto en ambos temas', (
    tester,
  ) async {
    for (final (tema, palette) in [
      (ThemeData(brightness: Brightness.light), AppPalette.light),
      (ThemeData(brightness: Brightness.dark), AppPalette.dark),
    ]) {
      late Color acento;
      await tester.pumpWidget(
        MaterialApp(
          theme: tema,
          home: Builder(
            builder: (context) {
              acento = acentoMarca(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Sobre la superficie (ítem seleccionado de la barra inferior, chips).
      expect(contraste(acento, palette.surface), greaterThanOrEqualTo(aa));
      // Ámbar puro sobre la superficie clara: por qué no se usa directo.
      if (tema.brightness == Brightness.light) {
        expect(contraste(AppColores.primary, palette.surface), lessThan(3));
      }
    }
  });
}
