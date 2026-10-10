import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/theme/app_theme.dart';
import 'package:taxi_app/features/admin/admin_usuario_filtros.dart';
import 'package:taxi_app/widgets/dialogo_dias_membresia.dart';

void main() {
  final ahora = DateTime(2026, 10, 9, 12);

  group('esUsuarioNuevo', () {
    test('registrado hace menos de 7 días: nuevo', () {
      final data = {
        'createdAt': Timestamp.fromDate(
          ahora.subtract(const Duration(days: 2)),
        ),
      };
      expect(esUsuarioNuevo(data, ahora: ahora), isTrue);
    });

    test('registrado hace más de 7 días: no', () {
      final data = {
        'createdAt': Timestamp.fromDate(
          ahora.subtract(const Duration(days: 9)),
        ),
      };
      expect(esUsuarioNuevo(data, ahora: ahora), isFalse);
    });

    test('usa fechaRegistro en altas viejas; sin fecha: no', () {
      final viejo = {
        'fechaRegistro': Timestamp.fromDate(
          ahora.subtract(const Duration(days: 1)),
        ),
      };
      expect(esUsuarioNuevo(viejo, ahora: ahora), isTrue);
      expect(esUsuarioNuevo(<String, dynamic>{}, ahora: ahora), isFalse);
    });
  });

  group('registroCompleto: solo se listan los que terminaron', () {
    test('con la bandera y la foto: completo', () {
      expect(
        registroCompleto({'isProfileComplete': true, 'foto': 'https://f'}),
        isTrue,
      );
    });

    test('sin foto, sin bandera o solo el token: no', () {
      expect(
        registroCompleto({'isProfileComplete': true, 'foto': ''}),
        isFalse,
      );
      expect(registroCompleto({'foto': 'https://f'}), isFalse);
      expect(registroCompleto({'fcmToken': 't'}), isFalse);
    });

    test('"Nuevo" cuenta desde que completó el registro', () {
      final completado = ahora.subtract(const Duration(days: 1));
      final data = {
        'createdAt': Timestamp.fromDate(
          ahora.subtract(const Duration(days: 40)),
        ),
        'perfilCompletadoAt': Timestamp.fromDate(completado),
      };
      expect(fechaRegistro(data), completado);
      expect(esUsuarioNuevo(data, ahora: ahora), isTrue);
    });
  });

  group('estadoConductor', () {
    test('pidió activación y no tiene membresía: pendiente', () {
      expect(
        estadoConductor({'solicitudConductor': true}),
        EstadoConductor.pendiente,
      );
    });

    test('membresía activa vigente: activo', () {
      expect(
        estadoConductor({
          'solicitudConductor': true,
          'membresia': 'activa',
          'membresiaVence': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 3)),
          ),
        }),
        EstadoConductor.activo,
      );
    });

    test('membresía vencida y sin solicitud: inactivo', () {
      expect(
        estadoConductor({
          'rol': 'conductor',
          'membresia': 'activa',
          'membresiaVence': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 1)),
          ),
        }),
        EstadoConductor.inactivo,
      );
    });
  });

  group('conductores pendientes: más recientes primero', () {
    test('usa solicitudConductorAt y si no, updatedAt', () {
      final t = Timestamp.fromDate(ahora);
      expect(fechaSolicitudConductor({'solicitudConductorAt': t}), ahora);
      expect(fechaSolicitudConductor({'updatedAt': t}), ahora);
      expect(fechaSolicitudConductor(<String, dynamic>{}), isNull);
    });

    test('ordena del más reciente al más antiguo; sin fecha al final', () {
      final fechas = [
        DateTime(2026, 10, 1),
        null,
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 5),
      ]..sort(masRecientePrimero);
      expect(fechas, [
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 1),
        null,
      ]);
    });
  });

  test('textoDias: singular y plural', () {
    expect(textoDias(1), '1 día');
    expect(textoDias(30), '30 días');
  });

  testWidgets('activar membresía: 1 día primero y preseleccionado', (
    tester,
  ) async {
    int? elegido;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: AppThemeConfig.lightTheme,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  elegido = await mostrarDialogoDiasMembresia(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final campo = tester.widget<TextField>(find.byType(TextField));
    expect(campo.controller!.text, '1');
    expect(find.text('día'), findsWidgets);

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();
    expect(elegido, 1);
  });
}
