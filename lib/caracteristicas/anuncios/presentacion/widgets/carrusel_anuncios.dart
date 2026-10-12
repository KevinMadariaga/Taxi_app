import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/anuncio.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import 'detalle_anuncio.dart';
import 'tarjeta_anuncio.dart';

/// Carrusel del inicio del cliente: los anuncios vigentes que sube el admin
/// y al final [tarjetaFinal] ("¿Quieres promocionar tu negocio?"). Pasa
/// solo cada [intervalo]; si la persona lo desliza, el conteo vuelve a
/// empezar.
class CarruselAnuncios extends StatefulWidget {
  const CarruselAnuncios({
    super.key,
    required this.tarjetaFinal,
    this.intervalo = const Duration(seconds: 10),
    AnunciosRepository? repositorio,
  }) : _repositorio = repositorio;

  final Widget tarjetaFinal;
  final Duration intervalo;
  final AnunciosRepository? _repositorio;

  @override
  State<CarruselAnuncios> createState() => _CarruselAnunciosState();
}

class _CarruselAnunciosState extends State<CarruselAnuncios> {
  late final Stream<List<Anuncio>> _stream =
      (widget._repositorio ?? AnunciosRepositoryImpl()).watchAnuncios();
  final PageController _controller = PageController();
  List<Anuncio> _todos = const [];
  int _pagina = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reiniciarTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _reiniciarTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.intervalo, (_) => _avanzar());
  }

  void _avanzar() {
    // Re-filtra en cada vuelta: un anuncio que venció deja de salir.
    setState(() {});
    final total = _vigentes.length + 1;
    if (total < 2 || !_controller.hasClients) return;
    final siguiente = (_pagina + 1) % total;
    _controller.animateToPage(
      siguiente,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  List<Anuncio> get _vigentes {
    final ahora = DateTime.now();
    return _todos.where((a) => a.vigente(ahora)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Anuncio>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasData) _todos = snap.data!;
        final anuncios = _vigentes;
        final total = anuncios.length + 1;
        if (_pagina >= total) _pagina = 0;
        return Stack(
          children: [
            NotificationListener<ScrollStartNotification>(
              onNotification: (n) {
                if (n.dragDetails != null) _reiniciarTimer();
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: total,
                onPageChanged: (i) => setState(() => _pagina = i),
                itemBuilder: (context, i) => i < anuncios.length
                    ? _ImagenAnuncio(anuncios[i])
                    : widget.tarjetaFinal,
              ),
            ),
            if (total > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: _Puntos(total: total, actual: _pagina),
              ),
          ],
        );
      },
    );
  }
}

class _ImagenAnuncio extends StatelessWidget {
  const _ImagenAnuncio(this.anuncio);

  final Anuncio anuncio;

  @override
  Widget build(BuildContext context) {
    return TarjetaAnuncio(
      conDetalle: anuncio.tieneDetalle,
      onTap: anuncio.tieneDetalle
          ? () => mostrarDetalleAnuncio(context, anuncio)
          : null,
      imagen: CachedNetworkImage(
        imageUrl: anuncio.imagenUrl,
        fit: BoxFit.cover,
        placeholder: (context, _) => ColoredBox(color: context.palette.grey100),
        errorWidget: (context, _, _) => ColoredBox(
          color: context.palette.grey100,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      ),
    );
  }
}

class _Puntos extends StatelessWidget {
  const _Puntos({required this.total, required this.actual});

  final int total;
  final int actual;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == actual ? 18 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == actual
                  ? AppColores.ink900
                  : Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black26, width: 0.5),
            ),
          ),
      ],
    );
  }
}
