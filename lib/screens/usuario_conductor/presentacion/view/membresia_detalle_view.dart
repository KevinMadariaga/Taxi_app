import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/widgets/dialogo_dias_membresia.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

/// Detalle de la membresía del conductor. Se abre al tocar la tarjeta
/// "Estás activo" en el perfil del conductor.
///
/// Resuelve sus propios datos a partir de [uid] (en vez de recibir el mapa
/// completo del padre) para no acoplar esta pantalla al ciclo de carga de
/// `PaginaPerfilUsuario`.
class MembresiaDetalleView extends StatefulWidget {
  const MembresiaDetalleView({super.key, required this.uid});

  final String uid;

  @override
  State<MembresiaDetalleView> createState() => _MembresiaDetalleViewState();
}

class _MembresiaDetalleViewState extends State<MembresiaDetalleView> {
  late final Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = UserDataService().getUsuario(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: appBarNeutra(context, titulo: 'Mi membresía'),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return _MembresiaDetalleContent(
          data: snapshot.data ?? const <String, dynamic>{},
        );
      },
    );
  }
}

class _MembresiaDetalleContent extends StatelessWidget {
  const _MembresiaDetalleContent({required this.data});

  final Map<String, dynamic> data;

  String _fecha(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final activa =
        (data['membresia'] ?? '').toString().toLowerCase() == 'activa';
    final dias = int.tryParse('${data['membresiaDias'] ?? ''}');
    final inicio = data['membresiaInicio'];
    final vence = data['membresiaVence'];

    int? restantes;
    if (vence is Timestamp) {
      restantes = vence
          .toDate()
          .difference(DateTime.now())
          .inDays
          .clamp(0, 9999);
    }
    final progreso = activa && dias != null && dias > 0 && restantes != null
        ? (restantes / dias).clamp(0.0, 1.0)
        : null;
    final color = activa ? AppColores.success : AppColores.error;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Mi membresía'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        color.withValues(alpha: 0.10),
                        palette.surface,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            activa
                                ? Icons.workspace_premium_rounded
                                : Icons.lock_clock_outlined,
                            color: color,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          activa ? 'Membresía activa' : 'Membresía inactiva',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activa
                              ? 'Puedes recibir y aceptar viajes.'
                              : 'No puedes aceptar viajes hasta activarla.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: palette.textSecondary,
                          ),
                        ),
                        if (activa && restantes != null) ...[
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$restantes',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                  color: palette.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                restantes == 1
                                    ? 'día restante'
                                    : 'días restantes',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (progreso != null) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progreso,
                              minHeight: 8,
                              backgroundColor: color.withValues(alpha: 0.18),
                              color: color,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SeccionAgrupada(
                    titulo: 'Detalles',
                    children: [
                      FilaDato(
                        icono: Icons.timelapse_rounded,
                        etiqueta: 'Plan contratado',
                        valor: dias != null ? textoDias(dias) : '—',
                      ),
                      FilaDato(
                        icono: Icons.event_available_outlined,
                        etiqueta: 'Inicio',
                        valor: _fecha(inicio),
                      ),
                      FilaDato(
                        icono: Icons.event_busy_outlined,
                        etiqueta: 'Vence',
                        valor: _fecha(vence),
                      ),
                    ],
                  ),
                  if (!activa) ...[
                    const SizedBox(height: 18),
                    SeccionAgrupada(
                      titulo: '¿Cómo la activo?',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text(
                            'Un administrador revisa tu registro y activa tu '
                            'membresía por los días acordados. Escríbenos si '
                            'ya pagaste o tienes dudas.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        FilaOpcion(
                          icono: Icons.support_agent_rounded,
                          titulo: 'Hablar con soporte',
                          destacado: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SoporteChatScreen(
                                userType: 'conductor',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
