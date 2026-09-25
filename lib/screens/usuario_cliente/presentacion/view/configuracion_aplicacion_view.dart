import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/theme_controller.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/eliminar_cuenta_screen.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ConfiguracionAplicacionView extends StatefulWidget {
  const ConfiguracionAplicacionView({super.key});

  @override
  State<ConfiguracionAplicacionView> createState() =>
      _ConfiguracionAplicacionViewState();
}

class _ConfiguracionAplicacionViewState
    extends State<ConfiguracionAplicacionView> {
  String _appVersion = '...';

  bool _isLoggingOut = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = info.version;
      });
    } catch (_) {
      // Ignore; keep placeholder
    }
  }

  String _etiquetaTema(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Oscuro';
      case ThemeMode.system:
        return 'Sistema';
    }
  }

  Future<void> _seleccionarApariencia() async {
    final controller = context.read<ThemeController>();
    final seleccionado = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) =>
          _SeleccionarAparienciaDialog(actual: controller.themeMode),
    );
    if (seleccionado == null) return;
    await controller.setThemeMode(seleccionado);
  }

  Future<void> _abrirDocumentosLegales() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _DocumentosLegalesView()));
  }

  Future<void> _cerrarSesion() async {
    if (_isLoggingOut || _isDeletingAccount) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmarCerrarSesionDialog(),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isLoggingOut = true);

    // Navegar ANTES de cerrar sesión, no después.
    //
    // `pushNamedAndRemoveUntil` desmonta todo el árbol anterior, y los
    // `dispose()` de esos ViewModels cancelan sus listeners de Firestore. Con
    // el orden inverso, el `signOut()` les quitaba la autenticación mientras
    // seguían suscritos y cada uno reventaba con `permission-denied`: en el
    // home del conductor eran cinco por cierre de sesión (`usuarios/{uid}`,
    // `soporte_chats/{uid}/mensajes`, las pendientes y las asignadas), todos
    // reportados a Crashlytics como errores reales.
    //
    // La sesión sigue activa durante la navegación, así que
    // `logout()` conserva el `currentUser` que necesita para desvincular el
    // token FCM.
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(RutasApp.login, (route) => false);

    // Sin `context` de acá en adelante: este State ya fue desmontado.
    await AuthService().logout();
  }

  Future<void> _eliminarCuenta() async {
    if (_isDeletingAccount || _isLoggingOut) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Eliminar cuenta'),
          content: const Text(
            'Vas a iniciar el proceso para eliminar tu cuenta de forma permanente. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EliminarCuentaScreen()));
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final temaActual = context.watch<ThemeController>().themeMode;

    final palette = context.palette;
    final ocupado = _isLoggingOut || _isDeletingAccount;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;

    Widget valor(String texto) => Text(
      texto,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
      ),
    );

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Configuración'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeccionAgrupada(
                    titulo: 'Preferencias',
                    children: [
                      FilaOpcion(
                        icono: Icons.dark_mode_outlined,
                        titulo: 'Apariencia',
                        subtitulo: 'Claro, oscuro o según tu dispositivo',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            valor(_etiquetaTema(temaActual)),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: palette.textSecondary.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ],
                        ),
                        onTap: _seleccionarApariencia,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SeccionAgrupada(
                    titulo: 'Información',
                    children: [
                      FilaOpcion(
                        icono: Icons.policy_outlined,
                        titulo: 'Documentos legales',
                        subtitulo: 'Términos y política de privacidad',
                        onTap: _abrirDocumentosLegales,
                      ),
                      FilaOpcion(
                        icono: Icons.info_outline_rounded,
                        titulo: 'Versión de la aplicación',
                        trailing: valor(_appVersion),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SeccionAgrupada(
                    titulo: 'Cuenta',
                    children: [
                      FilaOpcion(
                        icono: Icons.logout_rounded,
                        titulo: _isLoggingOut
                            ? 'Cerrando sesión…'
                            : 'Cerrar sesión',
                        peligro: true,
                        trailing: _isLoggingOut ? _spinner() : null,
                        onTap: ocupado ? null : _cerrarSesion,
                      ),
                      FilaOpcion(
                        icono: Icons.delete_outline_rounded,
                        titulo: _isDeletingAccount
                            ? 'Abriendo eliminación…'
                            : 'Eliminar cuenta',
                        subtitulo: 'Borra tu cuenta y tus datos de Ride',
                        peligro: true,
                        trailing: _isDeletingAccount ? _spinner() : null,
                        onTap: ocupado ? null : _eliminarCuenta,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// Modal de selección de apariencia: Sistema/Claro/Oscuro con `RadioListTile`,
/// devuelve el `ThemeMode` elegido (`null` si se cerró sin elegir).
class _SeleccionarAparienciaDialog extends StatelessWidget {
  const _SeleccionarAparienciaDialog({required this.actual});

  final ThemeMode actual;

  static const _opciones = [
    (ThemeMode.system, 'Sistema', 'Sigue el ajuste del dispositivo'),
    (ThemeMode.light, 'Claro', null),
    (ThemeMode.dark, 'Oscuro', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Apariencia',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<ThemeMode>(
              groupValue: actual,
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (mode, etiqueta, subtitulo) in _opciones)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      activeColor: AppColores.buttonPrimary,
                      title: Text(etiqueta),
                      subtitle: subtitulo == null ? null : Text(subtitulo),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal de confirmación de cierre de sesión con el estilo de botón propio
/// de la app (mismo radio/alto que los CTA del flujo de viaje) y las
/// acciones centradas lado a lado, en vez de las acciones de un
/// [AlertDialog] por defecto (que quedan alineadas a la derecha).
class _ConfirmarCerrarSesionDialog extends StatelessWidget {
  const _ConfirmarCerrarSesionDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColores.buttonCancel.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColores.buttonCancel,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Cerrar sesión',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '¿Deseas cerrar sesión en esta cuenta?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.palette.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        side: BorderSide(color: context.palette.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Cancelar',
                          maxLines: 1,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.buttonCancel,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Cerrar sesión',
                          maxLines: 1,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentosLegalesView extends StatelessWidget {
  const _DocumentosLegalesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarNeutra(context, titulo: 'Documentos legales'),
      backgroundColor: context.palette.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: const [
          _LegalCard(
            title: 'Términos y condiciones',
            content:
                'Condiciones de uso de Ride para pasajeros y conductores: viajes, pagos, cancelaciones y responsabilidades.',
            asset: 'assets/legal/terminos_condiciones.txt',
          ),
          SizedBox(height: 12),
          _LegalCard(
            title: 'Política de privacidad',
            content:
                'Cómo recopilamos, usamos, compartimos y protegemos tu información personal.',
            asset: 'assets/legal/politica_privacidad.txt',
          ),
        ],
      ),
    );
  }
}

class _DocumentoLegalView extends StatelessWidget {
  const _DocumentoLegalView({required this.title, required this.asset});

  final String title;
  final String asset;

  static final _encabezado = RegExp(r'^(\d+(\.\d+)*\.?\s|[A-ZÁÉÍÓÚÑ ]{8,}$)');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarNeutra(context, titulo: title),
      backgroundColor: context.palette.background,
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('No se pudo cargar el documento.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lineas = snap.data!
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          return SelectionArea(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                32 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              itemCount: lineas.length,
              itemBuilder: (context, i) {
                final linea = lineas[i];
                final esEncabezado =
                    linea.length < 60 && _encabezado.hasMatch(linea);
                return Padding(
                  padding: EdgeInsets.only(
                    top: esEncabezado && i > 0 ? 14 : 0,
                    bottom: 6,
                    left: linea.startsWith('•') ? 8 : 0,
                  ),
                  child: Text(
                    linea,
                    style: TextStyle(
                      fontSize: esEncabezado ? 16 : 14,
                      fontWeight: esEncabezado
                          ? FontWeight.w700
                          : FontWeight.normal,
                      color: esEncabezado
                          ? context.palette.textPrimary
                          : context.palette.textSecondary,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({
    required this.title,
    required this.content,
    required this.asset,
  });

  final String title;
  final String content;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.palette.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _DocumentoLegalView(title: title, asset: asset),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
