import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_chat_screen.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

typedef PreguntaFrecuente = ({String pregunta, String respuesta});

const List<PreguntaFrecuente> preguntasCliente = [
  (
    pregunta: '¿Cómo solicito un viaje?',
    respuesta:
        'Toca "¿A dónde vamos?", elige tu destino y confirma la solicitud '
        'para empezar a buscar conductor.',
  ),
  (
    pregunta: '¿Cómo cambio mi método de pago?',
    respuesta:
        'En la confirmación del viaje toca el método de pago y elige entre '
        'las opciones disponibles.',
  ),
  (
    pregunta: '¿Qué hago si no aparece ningún conductor?',
    respuesta:
        'Revisa tu conexión y que el GPS esté activo. Si pasan unos minutos '
        'puedes subir tu oferta o seguir esperando.',
  ),
  (
    pregunta: '¿Cómo reporto un problema con un viaje?',
    respuesta:
        'Escríbenos desde Soporte con los detalles del viaje y te '
        'ayudaremos a resolverlo.',
  ),
];

const List<PreguntaFrecuente> preguntasConductor = [
  (
    pregunta: '¿Cómo activo mi cuenta de conductor?',
    respuesta:
        'Completa tu registro de conductor. Un administrador revisa tus '
        'datos y activa tu membresía para que empieces a recibir viajes.',
  ),
  (
    pregunta: '¿Cómo acepto una solicitud de viaje?',
    respuesta:
        'Cuando llegue una solicitud aparecerá en pantalla. Toca "Aceptar" '
        'para tomar el viaje.',
  ),
  (
    pregunta: '¿Qué hago si no recibo solicitudes?',
    respuesta:
        'Verifica que estés conectado, que el GPS esté activo, que tengas '
        'internet y que tu membresía esté vigente.',
  ),
  (
    pregunta: '¿Cómo actualizo los datos de mi vehículo?',
    respuesta:
        'Ve a Perfil → "Cambiar de vehículo" para actualizar el tipo, la '
        'foto y la placa.',
  ),
  (
    pregunta: '¿Cómo contacto al administrador?',
    respuesta:
        'Escribe desde Soporte: el equipo te responde por el chat de la '
        'app.',
  ),
  (
    pregunta: '¿Cómo veo mi historial de viajes?',
    respuesta:
        'En "Más opciones" elige Historial para ver tus viajes con tarifa '
        'y ganancias.',
  ),
];

/// Preguntas frecuentes con buscador. Misma pantalla para cliente y
/// conductor; cambian las preguntas y a qué chat de soporte lleva.
class AyudaView extends StatefulWidget {
  const AyudaView({
    super.key,
    this.preguntas = preguntasCliente,
    this.userType = 'cliente',
  });

  final List<PreguntaFrecuente> preguntas;
  final String userType;

  @override
  State<AyudaView> createState() => _AyudaViewState();
}

class _AyudaViewState extends State<AyudaView> {
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final horizontal = resp.deviceType == DeviceType.mobile
        ? resp.screenWidth * 0.05
        : 32.0;
    final query = _query.toLowerCase().trim();
    final filtradas = widget.preguntas
        .where(
          (p) =>
              query.isEmpty ||
              p.pregunta.toLowerCase().contains(query) ||
              p.respuesta.toLowerCase().contains(query),
        )
        .toList();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Ayuda'),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '¿En qué te ayudamos?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onTapOutside: (_) => _searchFocusNode.unfocus(),
                    onChanged: (v) => setState(() => _query = v),
                    cursorColor: AppColores.primary,
                    style: TextStyle(color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Buscar una pregunta',
                      hintStyle: TextStyle(color: palette.textSecondary),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: palette.textSecondary,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar búsqueda',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: palette.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: palette.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColores.primary,
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (filtradas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 40,
                            color: palette.textSecondary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No encontramos esa pregunta.',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    SeccionAgrupada(
                      titulo: 'Preguntas frecuentes',
                      children: [
                        for (final p in filtradas) _PreguntaTile(pregunta: p),
                      ],
                    ),
                  const SizedBox(height: 18),
                  SeccionAgrupada(
                    titulo: '¿Necesitas más ayuda?',
                    children: [
                      FilaOpcion(
                        icono: Icons.support_agent_rounded,
                        titulo: 'Hablar con soporte',
                        subtitulo: 'Escríbenos por el chat de la app',
                        destacado: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SoporteChatScreen(userType: widget.userType),
                          ),
                        ),
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

class _PreguntaTile extends StatelessWidget {
  const _PreguntaTile({required this.pregunta});

  final PreguntaFrecuente pregunta;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Theme(
      // Sin las líneas que `ExpansionTile` dibuja arriba y abajo al abrirse:
      // la tarjeta ya separa las filas.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        iconColor: acentoMarca(context),
        collapsedIconColor: palette.textSecondary,
        expandedAlignment: Alignment.centerLeft,
        title: Text(
          pregunta.pregunta,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        children: [
          Text(
            pregunta.respuesta,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
