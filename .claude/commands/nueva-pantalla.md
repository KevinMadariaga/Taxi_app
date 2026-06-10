# nueva-pantalla

Crea una nueva pantalla Flutter para el proyecto Taxi Ya con:
- Diseño responsivo usando `flutter_screenutil` (`.w`, `.h`, `.sp`, `.r`)
- Colores de `AppColores` (importado desde `package:taxi_app/core/app_colores.dart`)
- Botones con `CustomButton` (importado desde `package:taxi_app/widgets/boton.dart`)
- Notificaciones locales opcionales via `NotificacionesServicio`
- Arquitectura MVVM: `StatefulWidget` + `ChangeNotifier` separado si hay lógica

## Pasos obligatorios antes de generar código

1. **Pregunta el nombre de la pantalla** (clase en PascalCase, ej. `HistorialViajesView`).
2. **Pregunta si necesita notificaciones locales** (sí/no).
   - Si sí: **pregunta el nombre o tema de la notificación** (ej. "Viaje asignado", "Pago recibido").
3. **Pregunta la ruta del archivo** (ej. `lib/screens/usuario_cliente/presentacion/view/`).

No generes código hasta tener las 3 respuestas.

## Plantilla base (adaptar con los datos recogidos)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';
// Si notificaciones: import 'package:taxi_app/core/services/notificacion_servicio.dart';

class NombrePantallaView extends StatefulWidget {
  const NombrePantallaView({super.key});

  @override
  State<NombrePantallaView> createState() => _NombrePantallaViewState();
}

class _NombrePantallaViewState extends State<NombrePantallaView> {
  bool _cargando = false;

  // Si notificaciones:
  // Future<void> _mostrarNotificacion() async {
  //   await NotificacionesServicio.instance.showNotification(
  //     id: 'nombre_pantalla'.hashCode,
  //     title: 'Título notificación',
  //     body: 'Cuerpo de la notificación',
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Título pantalla'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tarjeta ejemplo
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColores.cardBackground,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: AppColores.borderSubtle,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColores.borderSubtle,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'Contenido de la pantalla',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: AppColores.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              SizedBox(height: 24.h),

              // Texto secundario
              Text(
                'Descripción o información adicional',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColores.textSecondary,
                ),
              ),

              SizedBox(height: 32.h),

              // Botón primario
              CustomButton(
                text: 'Acción principal',
                isLoading: _cargando,
                onPressed: _cargando ? null : _onAccionPrincipal,
                height: 50.h,
                fontSize: 15.sp,
              ),

              SizedBox(height: 12.h),

              // Botón secundario (outline)
              SizedBox(
                height: 48.h,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColores.textPrimary,
                    side: const BorderSide(color: AppColores.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15.r),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAccionPrincipal() async {
    setState(() => _cargando = true);
    try {
      // lógica aquí
      // Si notificaciones: await _mostrarNotificacion();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }
}
```

## Reglas de generación

- **Nombres**: clase en `PascalCase`, archivo en `snake_case_view.dart`.
- **Colores**: usar SOLO constantes de `AppColores`. Prohibido `Colors.xxx` para colores de marca (permitido solo para `Colors.white`, `Colors.transparent`, `Colors.black` como overlay).
- **Tamaños**: todos los números de tamaño con ScreenUtil: `16.w`, `20.h`, `14.sp`, `12.r`. Sin valores fijos en pixeles desnudos para layout.
- **Botón primario**: siempre `CustomButton`. Botones secundarios con `OutlinedButton` + `borderRadius: 15.r` y `side: BorderSide(color: AppColores.primary)`.
- **AppBar**: `backgroundColor: AppColores.primary`, `foregroundColor: AppColores.textPrimary`, `elevation: 0`.
- **Notificación**: si el usuario dijo que sí, importar `NotificacionesServicio` y llamar `showNotification` con `id: 'nombre_unico'.hashCode`, el título y cuerpo que el usuario especificó.
- **Sin comentarios** salvo que el "por qué" no sea obvio.
- **No crear ViewModel separado** a menos que haya lógica de negocio compleja (más de 3 métodos async o llamadas a Firestore).
- Después de generar el archivo, mostrar el path completo donde se guardó.
