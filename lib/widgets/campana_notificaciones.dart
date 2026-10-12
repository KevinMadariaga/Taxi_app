import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/bandeja_notificaciones.dart';
import 'package:taxi_app/core/services/fcm_service.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Campana con el número de notificaciones sin leer. Al tocarla muestra lo
/// que llegó y lo marca como leído.
class CampanaNotificaciones extends StatefulWidget {
  const CampanaNotificaciones({super.key, this.color});

  final Color? color;

  @override
  State<CampanaNotificaciones> createState() => _CampanaNotificacionesState();
}

class _CampanaNotificacionesState extends State<CampanaNotificaciones> {
  final _bandeja = BandejaNotificaciones.instance;

  @override
  void initState() {
    super.initState();
    _bandeja.cargar();
  }

  Future<void> _abrir() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ListaNotificaciones(),
    );
    await _bandeja.marcarTodasLeidas();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AvisoBandeja>>(
      valueListenable: _bandeja.avisos,
      builder: (context, _, _) {
        final n = _bandeja.noLeidos;
        return IconButton(
          tooltip: n == 0 ? 'Notificaciones' : '$n notificaciones sin leer',
          onPressed: _abrir,
          icon: Badge(
            isLabelVisible: n > 0,
            backgroundColor: AppColores.error,
            label: Text(n > 9 ? '9+' : '$n'),
            child: Icon(
              n > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: widget.color ?? context.palette.textPrimary,
            ),
          ),
        );
      },
    );
  }
}

class _ListaNotificaciones extends StatelessWidget {
  const _ListaNotificaciones();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bandeja = BandejaNotificaciones.instance;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ValueListenableBuilder<List<AvisoBandeja>>(
          valueListenable: bandeja.avisos,
          builder: (context, avisos, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notificaciones',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (avisos.isNotEmpty)
                        TextButton(
                          onPressed: bandeja.borrarTodo,
                          child: const Text('Borrar todo'),
                        ),
                    ],
                  ),
                ),
                if (avisos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 40,
                          color: palette.grey400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Aún no te han llegado notificaciones.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: avisos.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: palette.divider),
                      itemBuilder: (_, i) => _FilaAviso(aviso: avisos[i]),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilaAviso extends StatelessWidget {
  const _FilaAviso({required this.aviso});

  final AvisoBandeja aviso;

  static IconData _icono(String tipo) {
    if (tipo.contains('chat') || tipo.contains('soporte')) {
      return Icons.chat_bubble_rounded;
    }
    if (tipo == 'promo') return Icons.local_offer_rounded;
    if (tipo == 'membresia_activada') return Icons.verified_rounded;
    if (tipo == 'nueva_solicitud' || tipo.startsWith('trip')) {
      return Icons.local_taxi_rounded;
    }
    return Icons.notifications_rounded;
  }

  static String _hace(DateTime fecha) {
    final d = DateTime.now().difference(fecha);
    if (d.inMinutes < 1) return 'Ahora';
    if (d.inHours < 1) return 'Hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'Hace ${d.inHours} h';
    if (d.inDays == 1) return 'Ayer';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}';
  }

  /// Soporte abre el chat en vivo; una promoción, su ventana.
  bool get _abreChatSoporte => aviso.tipo == 'soporte_chat_respuesta';
  bool get _abrePromocion => aviso.tipo == 'promo' && aviso.entidad.isNotEmpty;
  bool get _tocable => _abreChatSoporte || _abrePromocion;

  void _abrir(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop(); // cierra la lista
    if (_abrePromocion) {
      FcmService.instance.abrirPromocion(aviso.entidad);
    } else {
      SoporteNotificationService.instance.abrirChat(nav);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _tocable ? () => _abrir(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColores.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icono(aviso.tipo),
                size: 20,
                color: AppColores.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          aviso.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: aviso.leido
                                ? FontWeight.w600
                                : FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _hace(aviso.fecha),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textSecondary,
                        ),
                      ),
                      if (!aviso.leido) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColores.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (aviso.cuerpo.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      aviso.cuerpo,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_tocable)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
