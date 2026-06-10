import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';

class NotificacionesConductorView extends StatefulWidget {
  const NotificacionesConductorView({super.key});

  @override
  State<NotificacionesConductorView> createState() =>
      _NotificacionesConductorViewState();
}

class _NotificacionesConductorViewState
    extends State<NotificacionesConductorView> {
  static const _kSolicitudes = 'conductor_noti_solicitudes';
  static const _kChat = 'conductor_noti_chat';
  static const _kSistema = 'conductor_noti_sistema';

  bool _solicitudes = true;
  bool _chat = true;
  bool _sistema = true;
  bool _hasPermission = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final permission = await PermissionsHelper.hasNotificationPermission();
    if (!mounted) return;
    setState(() {
      _solicitudes = prefs.getBool(_kSolicitudes) ?? true;
      _chat = prefs.getBool(_kChat) ?? true;
      _sistema = prefs.getBool(_kSistema) ?? true;
      _hasPermission = permission;
      _loading = false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _requestPermission() async {
    final granted = await PermissionsHelper.requestNotificationPermission();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso no concedido. Revisa la configuración del sistema.',
          ),
        ),
      );
    }
  }

  Future<void> _sendTestNotification() async {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero concede permiso de notificaciones.'),
        ),
      );
      return;
    }

    await NotificacionesServicio.instance.showNotification(
      title: 'Taxi Ya',
      body: 'Esta es una notificación de prueba.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notificación de prueba enviada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: AppColores.surface,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColores.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: Icon(
                    _hasPermission
                        ? Icons.check_circle_outline
                        : Icons.warning_amber,
                    color: _hasPermission
                        ? AppColores.success
                        : AppColores.warning,
                  ),
                  title: const Text('Permiso del sistema'),
                  subtitle: Text(
                    _hasPermission ? 'Concedido' : 'No concedido',
                  ),
                  trailing: TextButton(
                    onPressed: _requestPermission,
                    child: const Text('Activar'),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _solicitudes,
                  title: const Text('Nuevas solicitudes de viaje'),
                  subtitle: const Text(
                    'Recibe alertas cuando un cliente solicite un taxi.',
                  ),
                  onChanged: (v) {
                    setState(() => _solicitudes = v);
                    _save(_kSolicitudes, v);
                  },
                ),
                SwitchListTile(
                  value: _chat,
                  title: const Text('Mensajes de chat'),
                  subtitle: const Text(
                    'Notificaciones de mensajes durante el viaje.',
                  ),
                  onChanged: (v) {
                    setState(() => _chat = v);
                    _save(_kChat, v);
                  },
                ),
                SwitchListTile(
                  value: _sistema,
                  title: const Text('Avisos del sistema'),
                  subtitle: const Text(
                    'Actualizaciones y alertas importantes de la app.',
                  ),
                  onChanged: (v) {
                    setState(() => _sistema = v);
                    _save(_kSistema, v);
                  },
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FilledButton.icon(
                    onPressed: _sendTestNotification,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Enviar notificación de prueba'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
