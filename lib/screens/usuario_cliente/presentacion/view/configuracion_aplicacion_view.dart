import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/theme/theme_controller.dart';
import 'package:taxi_app/routes/app_routes.dart';
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
    ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de la aplicación'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
      ),
      backgroundColor: context.palette.background,
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Apariencia'),
            subtitle: Text('Actual: ${_etiquetaTema(temaActual)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _seleccionarApariencia,
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Documentos legales'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _abrirDocumentosLegales,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Versión de la aplicación'),
            subtitle: Text(_appVersion),
          ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: _isLoggingOut
                  ? context.palette.textSecondary
                  : AppColores.error,
            ),
            title: Text(
              _isLoggingOut ? 'Cerrando sesión...' : 'Cerrar sesión',
              style: TextStyle(
                color: _isLoggingOut
                    ? context.palette.textSecondary
                    : AppColores.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            enabled: !_isLoggingOut && !_isDeletingAccount,
            onTap: _cerrarSesion,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: _isDeletingAccount
                  ? context.palette.textSecondary
                  : AppColores.error,
            ),
            title: Text(
              _isDeletingAccount
                  ? 'Abriendo eliminación...'
                  : 'Eliminar cuenta',
              style: TextStyle(
                color: _isDeletingAccount
                    ? context.palette.textSecondary
                    : AppColores.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            enabled: !_isDeletingAccount && !_isLoggingOut,
            onTap: _eliminarCuenta,
          ),
        ],
      ),
    );
  }
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
      appBar: AppBar(
        title: const Text('Documentos legales'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
      ),
      backgroundColor: context.palette.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _LegalCard(
            title: 'Términos y condiciones',
            content:
                'Al usar la aplicación aceptas los términos del servicio, las políticas de uso y las condiciones de la plataforma de transporte.',
          ),
          SizedBox(height: 12),
          _LegalCard(
            title: 'Política de privacidad',
            content:
                'La aplicación utiliza datos de ubicación y contacto para operar el servicio de viajes, mejorar la seguridad y brindar soporte al usuario.',
          ),
        ],
      ),
    );
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.borderSubtle),
      ),
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
    );
  }
}
