import 'package:flutter/material.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

/// Soporte: chat con el equipo, preguntas frecuentes y horario de atención.
/// Misma pantalla para cliente y conductor ([userType]).
class SoporteView extends StatelessWidget {
  const SoporteView({super.key, this.userType = 'cliente'});

  final String userType;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Soporte'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EncabezadoIcono(
                    icono: Icons.support_agent_rounded,
                    titulo: 'Estamos para ayudarte',
                    descripcion:
                        'Escríbenos por el chat y un agente te responderá lo '
                        'antes posible.',
                  ),
                  const SizedBox(height: 24),
                  SeccionAgrupada(
                    titulo: 'Contacto',
                    children: [
                      FilaOpcion(
                        icono: Icons.chat_bubble_outline_rounded,
                        titulo: 'Chat en vivo',
                        subtitulo: 'Habla directamente con el equipo',
                        destacado: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SoporteChatScreen(userType: userType),
                          ),
                        ),
                      ),
                      FilaOpcion(
                        icono: Icons.help_outline_rounded,
                        titulo: 'Preguntas frecuentes',
                        subtitulo: 'Respuestas rápidas a dudas comunes',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AyudaView(
                              preguntas: userType == 'conductor'
                                  ? preguntasConductor
                                  : preguntasCliente,
                              userType: userType,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SeccionAgrupada(
                    titulo: 'Horario de atención',
                    children: [
                      FilaDato(
                        icono: Icons.schedule_rounded,
                        etiqueta: 'Lunes a viernes',
                        valor: '8:00 a.m. – 6:00 p.m.',
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
