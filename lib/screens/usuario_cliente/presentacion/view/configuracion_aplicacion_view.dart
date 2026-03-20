import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/screens/eliminar_cuenta_screen.dart';
import 'package:taxi_app/core/services/services.dart';

class ConfiguracionAplicacionView extends StatefulWidget {
  const ConfiguracionAplicacionView({super.key});

  @override
  State<ConfiguracionAplicacionView> createState() =>
      _ConfiguracionAplicacionViewState();
}

class _ConfiguracionAplicacionViewState
    extends State<ConfiguracionAplicacionView> {
  static const String _appVersion = '1.0.0+4';

  String _apariencia = 'Sistema';
  bool _isLoggingOut = false;
  bool _isDeletingAccount = false;

  Future<void> _seleccionarApariencia() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final opciones = ['Sistema', 'Claro', 'Oscuro'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final opcion in opciones)
                ListTile(
                  leading: Icon(
                    _apariencia == opcion
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: _apariencia == opcion
                        ? AppColores.buttonPrimary
                        : AppColores.textSecondary,
                  ),
                  title: Text(opcion),
                  onTap: () => Navigator.of(ctx).pop(opcion),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _apariencia) return;
    setState(() => _apariencia = selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Apariencia seleccionada: $selected')),
    );
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
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cerrar sesión'),
          content: const Text('¿Deseas cerrar sesión en esta cuenta?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cerrar sesión. Intenta de nuevo.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de la aplicación'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Apariencia'),
            subtitle: Text('Actual: $_apariencia'),
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
            subtitle: const Text(_appVersion),
          ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(
              Icons.logout,
              color: _isLoggingOut
                  ? AppColores.textSecondary
                  : AppColores.error,
            ),
            title: Text(
              _isLoggingOut ? 'Cerrando sesión...' : 'Cerrar sesión',
              style: TextStyle(
                color: _isLoggingOut
                    ? AppColores.textSecondary
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
                  ? AppColores.textSecondary
                  : AppColores.error,
            ),
            title: Text(
              _isDeletingAccount
                  ? 'Abriendo eliminación...'
                  : 'Eliminar cuenta',
              style: TextStyle(
                color: _isDeletingAccount
                    ? AppColores.textSecondary
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

class _DocumentosLegalesView extends StatelessWidget {
  const _DocumentosLegalesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos legales'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
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
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColores.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColores.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
