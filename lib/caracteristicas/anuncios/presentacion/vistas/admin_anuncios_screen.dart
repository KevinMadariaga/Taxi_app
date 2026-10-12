import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/anuncio.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import '../widgets/tarjeta_anuncio.dart';
import 'editor_anuncio_screen.dart';
import '../mensaje_error.dart';

/// Anuncios de negocios que rotan en el carrusel del inicio del cliente:
/// el admin sube imágenes (con duración opcional) y las borra.
class AdminAnunciosScreen extends StatefulWidget {
  const AdminAnunciosScreen({super.key, AnunciosRepository? repositorio})
    : _repositorio = repositorio;

  final AnunciosRepository? _repositorio;

  @override
  State<AdminAnunciosScreen> createState() => _AdminAnunciosScreenState();
}

class _AdminAnunciosScreenState extends State<AdminAnunciosScreen>
    with SingleTickerProviderStateMixin {
  /// "Publicados" (la lista) y "Crear" (el editor), como en Promociones.
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  late final Stream<List<Anuncio>> _anuncios = _repo.watchAnuncios();
  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Editar un anuncio publicado (crear va en la pestaña "Crear").
  Future<void> _abrirEditor([Anuncio? anuncio]) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EditorAnuncioScreen(editando: anuncio, repositorio: _repo),
      ),
    );
    if (guardado == true) {
      _avisar(anuncio == null ? 'Anuncio publicado.' : 'Anuncio actualizado.');
    }
  }

  Future<void> _eliminar(Anuncio anuncio) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Eliminar anuncio',
      mensaje: 'Deja de verse en el inicio de los pasajeros.',
      accion: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    try {
      await _repo.eliminarAnuncio(anuncio);
      _avisar('Anuncio eliminado.');
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'admin_anuncios: eliminar');
      _avisar(mensajeErrorAccion(e, accion: 'eliminar'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lista = StreamBuilder<List<Anuncio>>(
      stream: _anuncios,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('No se pudieron cargar.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final anuncios = snap.data!;
        return LayoutBuilder(
          builder: (context, c) {
            // Columnas por ancho disponible: 1 en teléfono, 2 en tablet,
            // 3 en pantallas anchas. La altura sale del ancho real de la
            // tarjeta (imagen 2:1 + fila de estado), así nunca desborda.
            final columnas = c.maxWidth < 600
                ? 1
                : c.maxWidth < 1100
                ? 2
                : 3;
            const pad = 16.0, gap = 14.0;
            final ancho =
                (c.maxWidth - pad * 2 - gap * (columnas - 1)) / columnas;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(pad, 12, pad, 16),
                  sliver: SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Text(
                          'Rotan cada 10 segundos en el inicio de los '
                          'pasajeros, junto a "¿Quieres promocionar tu '
                          'negocio?". Usa imágenes horizontales (por '
                          'ejemplo 1200×600).',
                          style: TextStyle(
                            color: palette.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (anuncios.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Aún no hay anuncios.',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () => _tabs.animateTo(1),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColores.primary,
                              foregroundColor: AppColores.ink900,
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Crear anuncio'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(pad, 0, pad, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnas,
                        crossAxisSpacing: gap,
                        mainAxisSpacing: gap,
                        mainAxisExtent: ancho / kProporcionAnuncio + 58,
                      ),
                      itemCount: anuncios.length,
                      itemBuilder: (_, i) => _TarjetaAnuncio(
                        anuncios[i],
                        onEditar: _abrirEditor,
                        onEliminar: _eliminar,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(
        context,
        titulo: 'Anuncios del inicio',
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColores.primary,
          indicatorWeight: 3,
          labelColor: palette.textPrimary,
          unselectedLabelColor: palette.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(icon: Icon(Icons.view_carousel_rounded), text: 'Publicados'),
            Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Crear'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          lista,
          EditorAnuncioScreen(
            repositorio: _repo,
            embebida: true,
            alGuardar: () {
              _tabs.animateTo(0);
              _avisar('Anuncio publicado.');
            },
          ),
        ],
      ),
    );
  }
}

class _TarjetaAnuncio extends StatelessWidget {
  const _TarjetaAnuncio(
    this.anuncio, {
    required this.onEditar,
    required this.onEliminar,
  });

  final Anuncio anuncio;
  final ValueChanged<Anuncio> onEditar;
  final ValueChanged<Anuncio> onEliminar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final vigente = anuncio.vigente(DateTime.now());
    final vence = anuncio.venceEn;
    final estado = vence == null
        ? 'Sin vencimiento'
        : vigente
        ? 'Vence el ${vence.day}/${vence.month} ${vence.hour.toString().padLeft(2, '0')}:${vence.minute.toString().padLeft(2, '0')}'
        : 'Vencido: ya no se muestra';
    return Card(
      elevation: 0,
      color: palette.surface,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La celda ya mide 2:1 + la fila: la imagen toma lo que sobre.
          Expanded(
            child: Opacity(
              opacity: vigente ? 1 : 0.45,
              child: TarjetaAnuncio(
                conDetalle: anuncio.tieneDetalle,
                onTap: () => onEditar(anuncio),
                imagen: CachedNetworkImage(
                  imageUrl: anuncio.imagenUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Icon(
                  vigente ? Icons.schedule_rounded : Icons.timer_off_outlined,
                  size: 18,
                  color: vigente ? palette.textSecondary : AppColores.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (anuncio.titulo.isNotEmpty)
                        Text(
                          anuncio.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                      Text(
                        estado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: anuncio.titulo.isEmpty ? 14 : 12,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  onPressed: () => onEditar(anuncio),
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: () => onEliminar(anuncio),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColores.error,
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
