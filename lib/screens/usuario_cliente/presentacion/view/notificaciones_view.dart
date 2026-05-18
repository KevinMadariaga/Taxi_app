import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';

class NotificacionesView extends StatefulWidget {
  const NotificacionesView({super.key});

  @override
  State<NotificacionesView> createState() => _NotificacionesViewState();
}

class _NotificacionesViewState extends State<NotificacionesView> {
  static const _kViajes = 'settings_noti_viajes';
  static const _kChat = 'settings_noti_chat';
  static const _kPromos = 'settings_noti_promos';
  static const _kSistema = 'settings_noti_sistema';

  bool _viajes = true;
  bool _chat = true;
  bool _promos = false;
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
      _viajes = prefs.getBool(_kViajes) ?? true;
      _chat = prefs.getBool(_kChat) ?? true;
      _promos = prefs.getBool(_kPromos) ?? false;
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
            'Permiso no concedido. Revisa la configuracion del sistema.',
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
      title: 'Taxi App',
      body: 'Esta es una notificacion de prueba.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notificacion de prueba enviada.')),
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
                  subtitle: Text(_hasPermission ? 'Concedido' : 'No concedido'),
                  trailing: TextButton(
                    onPressed: _requestPermission,
                    child: const Text('Activar'),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _viajes,
                  title: const Text('Notificaciones de viajes'),
                  onChanged: (v) {
                    setState(() => _viajes = v);
                    _save(_kViajes, v);
                  },
                ),
                SwitchListTile(
                  value: _chat,
                  title: const Text('Mensajes de chat'),
                  onChanged: (v) {
                    setState(() => _chat = v);
                    _save(_kChat, v);
                  },
                ),
                SwitchListTile(
                  value: _promos,
                  title: const Text('Promociones y novedades'),
                  onChanged: (v) {
                    setState(() => _promos = v);
                    _save(_kPromos, v);
                  },
                ),
                SwitchListTile(
                  value: _sistema,
                  title: const Text('Avisos del sistema'),
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
                    label: const Text('Enviar notificacion de prueba'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
