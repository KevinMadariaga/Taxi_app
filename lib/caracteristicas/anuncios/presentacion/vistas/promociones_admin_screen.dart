import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/promocion.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import '../widgets/ventana_promocion.dart';
import 'enviar_promocion_screen.dart';
import '../mensaje_error.dart';

String _textoPublico(AudienciaPromocion a) => switch (a) {
  AudienciaPromocion.clientes => 'Clientes',
  AudienciaPromocion.conductores => 'Conductores',
  AudienciaPromocion.todos => 'Todos',
};

IconData _iconoPublico(AudienciaPromocion a) => switch (a) {
  AudienciaPromocion.clientes => Icons.person_rounded,
  AudienciaPromocion.conductores => Icons.local_taxi_rounded,
  AudienciaPromocion.todos => Icons.groups_rounded,
};

String _fecha(DateTime? f) {
  if (f == null) return '—';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

/// Sección "Promoción" del panel admin: las enviadas (con su detalle) y
/// la pestaña para crear una nueva.
class PromocionesAdminScreen extends StatefulWidget {
  const PromocionesAdminScreen({super.key, AnunciosRepository? repositorio})
    : _repositorio = repositorio;

  final AnunciosRepository? _repositorio;

  @override
  State<PromocionesAdminScreen> createState() => _PromocionesAdminScreenState();
}

class _PromocionesAdminScreenState extends State<PromocionesAdminScreen>
    with SingleTickerProviderStateMixin {
  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final Stream<List<Promocion>> _promociones = _repo.watchPromociones();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: appBarNeutra(
        context,
        titulo: 'Promociones',
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColores.primary,
          labelColor: context.palette.textPrimary,
          unselectedLabelColor: context.palette.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(icon: Icon(Icons.history_rounded), text: 'Enviadas'),
            Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Crear'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ListaPromociones(
            repo: _repo,
            promociones: _promociones,
            onCrear: () => _tabs.animateTo(1),
          ),
          EnviarPromocionScreen(
            repositorio: _repo,
            embebida: true,
            alEnviar: () => _tabs.animateTo(0),
          ),
        ],
      ),
    );
  }
}

class _ListaPromociones extends StatelessWidget {
  const _ListaPromociones({
    required this.repo,
    required this.promociones,
    required this.onCrear,
  });

  final AnunciosRepository repo;
  final Stream<List<Promocion>> promociones;
  final VoidCallback onCrear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StreamBuilder<List<Promocion>>(
      stream: promociones,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('No se pudieron cargar.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lista = snap.data!;
        if (lista.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: 48,
                    color: palette.grey400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aún no has enviado promociones.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onCrear,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColores.primary,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear promoción'),
                  ),
                ],
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, c) {
            // 1 columna en teléfono, 2 en tablet, 3 en pantallas anchas.
            final columnas = c.maxWidth < 600
                ? 1
                : c.maxWidth < 1100
                ? 2
                : 3;
            // Filas de [columnas] tarjetas con el alto de su contenido (sin
            // alto fijo: la letra de accesibilidad agranda el texto).
            final filas = (lista.length / columnas).ceil();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filas,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, f) => IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var k = 0; k < columnas; k++) ...[
                      if (k > 0) const SizedBox(width: 12),
                      Expanded(
                        child: f * columnas + k < lista.length
                            ? _FilaPromocion(lista[f * columnas + k], repo)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _FilaPromocion extends StatelessWidget {
  const _FilaPromocion(this.promo, this.repo);

  final Promocion promo;
  final AnunciosRepository repo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final vigente = promo.vigente(DateTime.now());
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderSubtle),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetallePromocionScreen(promo, repositorio: repo),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Más chica en teléfonos angostos: deja lugar al texto.
              _Miniatura(
                promo: promo,
                lado: MediaQuery.sizeOf(context).width < 360 ? 64 : 88,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promo.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      promo.cuerpo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        _Etiqueta(
                          icono: _iconoPublico(promo.audiencia),
                          texto: _textoPublico(promo.audiencia),
                        ),
                        _Etiqueta(
                          icono: vigente
                              ? Icons.check_circle_rounded
                              : Icons.timer_off_outlined,
                          texto: vigente ? 'Vigente' : 'Vencida',
                          color: vigente
                              ? AppColores.success
                              : AppColores.error,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.promo, required this.lado});

  final Promocion promo;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final sinImagen = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColores.primary, AppColores.brand500],
        ),
      ),
      child: Icon(
        Icons.campaign_rounded,
        color: AppColores.ink900,
        size: lado * 0.45,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: lado,
        child: promo.imagenUrl.isEmpty
            ? sinImagen
            : CachedNetworkImage(
                imageUrl: promo.imagenUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => sinImagen,
              ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icono, required this.texto, this.color});

  final IconData icono;
  final String texto;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Detalle de una promoción enviada: imagen, texto completo, público,
/// fechas, estado y cómo la ven los usuarios.
class DetallePromocionScreen extends StatefulWidget {
  const DetallePromocionScreen(
    this.promocion, {
    super.key,
    AnunciosRepository? repositorio,
  }) : _repositorio = repositorio;

  final Promocion promocion;
  final AnunciosRepository? _repositorio;

  @override
  State<DetallePromocionScreen> createState() => _DetallePromocionScreenState();
}

class _DetallePromocionScreenState extends State<DetallePromocionScreen> {
  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  late Promocion promo = widget.promocion;

  Future<void> _editar() async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EnviarPromocionScreen(repositorio: _repo, editando: promo),
      ),
    );
    if (guardado != true || !mounted) return;
    final nueva = await _repo.obtenerPromocion(promo.id);
    if (!mounted) return;
    if (nueva != null) setState(() => promo = nueva);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Promoción actualizada.')));
  }

  Future<void> _eliminar() async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Eliminar promoción',
      mensaje:
          'Deja de aparecer en la app y en la lista. La notificación que ya '
          'llegó no se puede retirar.',
      accion: 'Eliminar',
      peligro: true,
    );
    if (!ok || !mounted) return;
    try {
      await _repo.eliminarPromocion(promo);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Promoción eliminada.')),
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'detalle_promocion: eliminar');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeErrorAccion(e, accion: 'eliminar'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final vigente = promo.vigente(DateTime.now());
    // Cuadrada: es como se recorta (en la ventana se ve en un círculo).
    final imagen = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1,
            child: promo.imagenUrl.isEmpty
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColores.primary, AppColores.brand500],
                      ),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      size: 64,
                      color: AppColores.ink900,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: promo.imagenUrl,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
    final datos = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          promo.titulo,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          promo.cuerpo,
          style: TextStyle(
            fontSize: 15.5,
            height: 1.45,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            children: [
              _Dato(
                icono: _iconoPublico(promo.audiencia),
                titulo: 'Público',
                valor: _textoPublico(promo.audiencia),
              ),
              Divider(height: 1, color: palette.divider),
              _Dato(
                icono: Icons.send_rounded,
                titulo: 'Enviada',
                valor: _fecha(promo.creadoEn),
              ),
              Divider(height: 1, color: palette.divider),
              _Dato(
                icono: Icons.event_rounded,
                titulo: 'Se muestra hasta',
                valor: _fecha(promo.venceEn),
              ),
              Divider(height: 1, color: palette.divider),
              _Dato(
                icono: vigente
                    ? Icons.check_circle_rounded
                    : Icons.timer_off_outlined,
                titulo: 'Estado',
                valor: vigente ? 'Vigente' : 'Vencida',
                color: vigente ? AppColores.success : AppColores.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => mostrarVentanaPromocion(context, promo),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.textPrimary,
              side: const BorderSide(color: AppColores.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text(
              'Ver como la ven los usuarios',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(
        context,
        titulo: 'Detalle de la promoción',
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _editar,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _eliminar,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColores.error,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final ancho = c.maxWidth >= 840;
            return SingleChildScrollView(
              padding: EdgeInsets.all(ancho ? 24 : 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ancho ? 1100 : 640),
                  child: ancho
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: imagen),
                            const SizedBox(width: 32),
                            Expanded(child: datos),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [imagen, const SizedBox(height: 18), datos],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icono, size: 20, color: color ?? AppColores.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(titulo, style: TextStyle(color: palette.textSecondary)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color ?? palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
