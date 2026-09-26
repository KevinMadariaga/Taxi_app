import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/comentarios_conductor_viewmodel.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

/// Comentarios que dejaron los pasajeros al calificar al conductor, con un
/// resumen (promedio de estrellas y cantidad) arriba.
class ComentariosConductorView extends StatefulWidget {
  const ComentariosConductorView({super.key});

  @override
  State<ComentariosConductorView> createState() =>
      _ComentariosConductorViewState();
}

class _ComentariosConductorViewState extends State<ComentariosConductorView> {
  // Una sola suscripción por pantalla: creados en `build` (como antes), cada
  // rebuild —tema, rotación— volvía a abrir el listener de Firestore.
  final _vm = ComentariosConductorViewModel();
  late final Stream<List<DriverCommentItem>> _stream = _vm.streamComentarios();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
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
      appBar: appBarNeutra(context, titulo: 'Comentarios de clientes'),
      body: _vm.conductorId.isEmpty
          ? const _Estado(
              icono: Icons.person_off_outlined,
              titulo: 'No pudimos identificarte',
              detalle: 'Vuelve a iniciar sesión e inténtalo de nuevo.',
            )
          : StreamBuilder<List<DriverCommentItem>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _Estado(
                    icono: Icons.cloud_off_rounded,
                    titulo: 'No se pudieron cargar',
                    detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return const _Estado(
                    icono: Icons.rate_review_outlined,
                    titulo: 'Aún no tienes comentarios',
                    detalle:
                        'Cuando un pasajero califique tu viaje y deje un '
                        'comentario, lo verás aquí.',
                  );
                }

                final resumen = resumenComentarios(items);
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 28),
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    final Widget hijo = i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: _Resumen(
                              promedio: resumen.promedio,
                              total: resumen.total,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TarjetaComentario(
                              item: items[i - 1],
                              fecha: _vm.formatDate(items[i - 1].createdAt),
                            ),
                          );
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: hijo,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.promedio, required this.total});

  final double promedio;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppColores.primary.withValues(alpha: 0.10),
          palette.surface,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColores.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Text(
            promedio > 0 ? promedio.toStringAsFixed(1) : '–',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Estrellas(valor: promedio, tamano: 20),
                const SizedBox(height: 4),
                Text(
                  total == 1
                      ? '1 comentario de pasajeros'
                      : '$total comentarios de pasajeros',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaComentario extends StatelessWidget {
  const _TarjetaComentario({required this.item, required this.fecha});

  final DriverCommentItem item;
  final String fecha;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final nombre = item.nombreCliente.isEmpty ? 'Pasajero' : item.nombreCliente;
    final tieneFecha = item.createdAt.millisecondsSinceEpoch > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColores.primary.withValues(alpha: 0.18),
                foregroundColor: acentoMarca(context),
                child: Text(
                  nombre[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (item.estrellas > 0) ...[
                      const SizedBox(height: 2),
                      _Estrellas(valor: item.estrellas, tamano: 15),
                    ],
                  ],
                ),
              ),
              if (tieneFecha)
                Text(
                  fecha,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 20,
                  color: AppColores.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.comment,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Estrellas extends StatelessWidget {
  const _Estrellas({required this.valor, required this.tamano});

  final double valor;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final llenas = valor.floor();
    final media = valor - llenas >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < llenas
                ? Icons.star_rounded
                : (i == llenas && media)
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: tamano,
            color: i < llenas || (i == llenas && media)
                ? AppColores.primary
                : palette.grey400,
          ),
      ],
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EncabezadoIcono(
          icono: icono,
          titulo: titulo,
          descripcion: detalle,
        ),
      ),
    );
  }
}
