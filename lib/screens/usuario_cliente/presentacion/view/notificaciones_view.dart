import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/permisos_helper.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/services/notificacion_servicio.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

/// Un interruptor de notificaciones: la [clave] de SharedPreferences no
/// debe cambiar, o se pierde lo que el usuario ya había elegido.
typedef OpcionNotificacion = ({
  String clave,
  String titulo,
  String subtitulo,
  IconData icono,
  bool porDefecto,
});

const List<OpcionNotificacion> opcionesNotificacionCliente = [
  (
    clave: 'settings_noti_viajes',
    titulo: 'Viajes',
    subtitulo: 'Conductor asignado, llegada y estado del viaje',
    icono: Icons.local_taxi_outlined,
    porDefecto: true,
  ),
  (
    clave: 'settings_noti_chat',
    titulo: 'Mensajes de chat',
    subtitulo: 'Lo que te escriba el conductor',
    icono: Icons.chat_bubble_outline_rounded,
    porDefecto: true,
  ),
  (
    clave: 'settings_noti_promos',
    titulo: 'Promociones y novedades',
    subtitulo: 'Descuentos y nuevas funciones',
    icono: Icons.local_offer_outlined,
    porDefecto: false,
  ),
  (
    clave: 'settings_noti_sistema',
    titulo: 'Avisos del sistema',
    subtitulo: 'Actualizaciones y alertas importantes',
    icono: Icons.campaign_outlined,
    porDefecto: true,
  ),
];

const List<OpcionNotificacion> opcionesNotificacionConductor = [
  (
    clave: 'conductor_noti_solicitudes',
    titulo: 'Nuevas solicitudes',
    subtitulo: 'Cuando un pasajero pida un viaje cerca',
    icono: Icons.notifications_active_outlined,
    porDefecto: true,
  ),
  (
    clave: 'conductor_noti_chat',
    titulo: 'Mensajes de chat',
    subtitulo: 'Lo que te escriba el pasajero durante el viaje',
    icono: Icons.chat_bubble_outline_rounded,
    porDefecto: true,
  ),
  (
    clave: 'conductor_noti_sistema',
    titulo: 'Avisos del sistema',
    subtitulo: 'Actualizaciones y alertas importantes',
    icono: Icons.campaign_outlined,
    porDefecto: true,
  ),
];

/// Ajustes de notificaciones. Misma pantalla para cliente y conductor;
/// cambian los interruptores ([opciones]).
class NotificacionesView extends StatefulWidget {
  const NotificacionesView({
    super.key,
    this.opciones = opcionesNotificacionCliente,
  });

  final List<OpcionNotificacion> opciones;

  @override
  State<NotificacionesView> createState() => _NotificacionesViewState();
}

class _NotificacionesViewState extends State<NotificacionesView> {
  final Map<String, bool> _valores = {};
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
      for (final o in widget.opciones) {
        _valores[o.clave] = prefs.getBool(o.clave) ?? o.porDefecto;
      }
      _hasPermission = permission;
      _loading = false;
    });
  }

  Future<void> _cambiar(String clave, bool valor) async {
    setState(() => _valores[clave] = valor);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(clave, valor);
  }

  Future<void> _requestPermission() async {
    final granted = await PermissionsHelper.requestNotificationPermission();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso no concedido. Actívalo desde los ajustes del teléfono.',
          ),
        ),
      );
    }
  }

  Future<void> _sendTestNotification() async {
    if (!_hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero activa el permiso de notificaciones.'),
        ),
      );
      return;
    }
    await NotificacionesServicio.instance.showNotification(
      title: 'Ride',
      body: 'Esta es una notificación de prueba.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notificación de prueba enviada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Notificaciones'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EstadoPermiso(
                          concedido: _hasPermission,
                          onActivar: _requestPermission,
                        ),
                        const SizedBox(height: 22),
                        SeccionAgrupada(
                          titulo: 'Qué quieres recibir',
                          children: [
                            for (final o in widget.opciones)
                              FilaOpcion(
                                icono: o.icono,
                                titulo: o.titulo,
                                subtitulo: o.subtitulo,
                                onTap: () =>
                                    _cambiar(o.clave, !_valores[o.clave]!),
                                trailing: Switch.adaptive(
                                  value: _valores[o.clave]!,
                                  activeTrackColor: AppColores.primary,
                                  onChanged: (v) => _cambiar(o.clave, v),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SeccionAgrupada(
                          titulo: 'Prueba',
                          children: [
                            FilaOpcion(
                              icono: Icons.send_outlined,
                              titulo: 'Enviar notificación de prueba',
                              subtitulo: 'Comprueba que te lleguen los avisos',
                              onTap: _sendTestNotification,
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
}

class _EstadoPermiso extends StatelessWidget {
  const _EstadoPermiso({required this.concedido, required this.onActivar});

  final bool concedido;
  final VoidCallback onActivar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = concedido ? AppColores.success : AppColores.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), palette.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              concedido
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  concedido
                      ? 'Notificaciones activadas'
                      : 'Notificaciones desactivadas',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  concedido
                      ? 'Te avisaremos de lo que elijas abajo.'
                      : 'Actívalas para no perderte tus viajes.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!concedido)
            TextButton(
              onPressed: onActivar,
              style: TextButton.styleFrom(
                foregroundColor: acentoMarca(context),
                iconColor: AppColores.primary,
              ),
              child: const Text(
                'Activar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}
