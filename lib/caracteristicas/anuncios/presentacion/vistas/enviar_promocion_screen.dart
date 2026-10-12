import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/promocion.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import '../mensaje_error.dart';

/// El admin arma una promoción (imagen opcional, título, mensaje, público y
/// vigencia). Llega por push y sale como modal en el inicio de cada usuario
/// del público elegido, una sola vez, mientras esté vigente.
class EnviarPromocionScreen extends StatefulWidget {
  const EnviarPromocionScreen({
    super.key,
    AnunciosRepository? repositorio,
    this.embebida = false,
    this.alEnviar,
    this.editando,
  }) : _repositorio = repositorio;

  /// Con valor: corrige esa promoción en vez de crear una (no reenvía la
  /// notificación).
  final Promocion? editando;

  final AnunciosRepository? _repositorio;

  /// Dentro de otra pantalla con su propia barra (la pestaña "Crear" de
  /// `PromocionesAdminScreen`): sin Scaffold ni AppBar propios.
  final bool embebida;

  /// Después de enviar con éxito (p. ej. volver a la lista).
  final VoidCallback? alEnviar;

  @override
  State<EnviarPromocionScreen> createState() => _EnviarPromocionScreenState();
}

class _EnviarPromocionScreenState extends State<EnviarPromocionScreen> {
  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  final _titulo = TextEditingController();
  final _cuerpo = TextEditingController();
  Uint8List? _imagen;

  /// La que ya tenía la promoción que se edita ('' = sin imagen).
  String _imagenActual = '';
  AudienciaPromocion _audiencia = AudienciaPromocion.todos;

  /// `null` solo al editar: deja la vigencia como estaba.
  int? _dias = 3;
  bool _enviando = false;
  String? _error;

  static const List<int> _opcionesDias = [1, 3, 7, 15, 30];

  bool get _editando => widget.editando != null;

  @override
  void initState() {
    super.initState();
    final p = widget.editando;
    if (p != null) {
      _titulo.text = p.titulo;
      _cuerpo.text = p.cuerpo;
      _imagenActual = p.imagenUrl;
      _audiencia = p.audiencia;
      _dias = null;
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen() async {
    final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    if (foto == null || !mounted) return;
    try {
      // La misma pantalla de recorte que la foto de perfil: cuadrada con
      // guía circular, como se ve en la ventana.
      final archivo = await const ImageCropperService().cropPromocionImage(
        sourcePath: foto.path,
      );
      final bytes = await archivo?.readAsBytes();
      if (bytes != null && mounted) setState(() => _imagen = bytes);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'enviar_promocion: recortar');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el recorte.')),
        );
      }
    }
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    final titulo = _titulo.text.trim();
    final cuerpo = _cuerpo.text.trim();
    if (titulo.isEmpty || cuerpo.isEmpty) {
      setState(() => _error = 'Escribe el título y el mensaje.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final editando = widget.editando;
      if (editando != null) {
        await _repo.actualizarPromocion(
          editando,
          titulo: titulo,
          cuerpo: cuerpo,
          audiencia: _audiencia,
          dias: _dias,
          nuevaImagen: _imagen,
          quitarImagen: _imagen == null && _imagenActual.isEmpty,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      await _repo.enviarPromocion(
        titulo: titulo,
        cuerpo: cuerpo,
        audiencia: _audiencia,
        diasVigencia: _dias ?? 3,
        imagen: _imagen,
      );
      if (!mounted) return;
      // Es una sección del panel (no una ruta que se cierra): queda lista
      // para la siguiente.
      _titulo.clear();
      _cuerpo.clear();
      setState(() {
        _enviando = false;
        _imagen = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Promoción enviada.')));
      widget.alEnviar?.call();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'enviar_promocion_screen');
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = mensajeErrorAccion(
          e,
          accion: _editando ? 'guardar' : 'enviar',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final intro = Text(
      _editando
          ? 'Los cambios se ven la próxima vez que abran la promoción. No se '
                'vuelve a enviar la notificación.'
          : 'Les llega como notificación y les sale como ventana en el inicio '
                'de la app, una sola vez.',
      style: TextStyle(color: palette.textSecondary, height: 1.35),
    );
    final imagen = _SelectorImagen(
      imagen: _imagen,
      imagenUrl: _imagenActual,
      onElegir: _enviando ? null : _elegirImagen,
      onQuitar: _enviando
          ? null
          : () => setState(() {
              _imagen = null;
              _imagenActual = '';
            }),
    );
    final formulario = <Widget>[
      TextField(
        controller: _titulo,
        maxLength: 80,
        maxLines: null,
        enabled: !_enviando,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Título'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _cuerpo,
        maxLength: 300,
        // Crece con el texto: la pantalla se desplaza, no el campo.
        minLines: 2,
        maxLines: null,
        enabled: !_enviando,
        textInputAction: TextInputAction.done,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: const InputDecoration(labelText: 'Mensaje'),
      ),
      const SizedBox(height: 12),
      const _Etiqueta('¿A quién le sale?'),
      const SizedBox(height: 8),
      _SelectorPublico(
        valor: _audiencia,
        onCambio: _enviando ? null : (a) => setState(() => _audiencia = a),
      ),
      const SizedBox(height: 16),
      const _Etiqueta('¿Hasta cuándo se muestra la ventana?'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_editando)
            ChipSeleccion(
              texto: 'Mantener',
              seleccionado: _dias == null,
              onSeleccionar: _enviando
                  ? null
                  : () => setState(() => _dias = null),
            ),
          for (final d in _opcionesDias)
            ChipSeleccion(
              texto: d == 1 ? '1 día' : '$d días',
              seleccionado: _dias == d,
              onSeleccionar: _enviando ? null : () => setState(() => _dias = d),
            ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: AppColores.error)),
        ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColores.primary,
            foregroundColor: Colors.black,
          ),
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Icon(_editando ? Icons.save_rounded : Icons.send_rounded),
          label: Text(
            _enviando
                ? (_editando ? 'Guardando...' : 'Enviando...')
                : (_editando ? 'Guardar cambios' : 'Enviar promoción'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];

    final cuerpo = SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          // Ancho: imagen a la izquierda y formulario a la derecha.
          if (c.maxWidth >= 840) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [intro, const SizedBox(height: 16), imagen],
                        ),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: formulario,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          // Angosto/mediano: una columna con ancho de lectura cómodo.
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    intro,
                    const SizedBox(height: 16),
                    imagen,
                    const SizedBox(height: 16),
                    ...formulario,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (widget.embebida) return cuerpo;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(
        context,
        titulo: _editando ? 'Editar promoción' : 'Enviar promoción',
      ),
      body: cuerpo,
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: TextStyle(
      fontWeight: FontWeight.w700,
      color: context.palette.textPrimary,
    ),
  );
}

/// Vista previa circular, como sale en la ventana de la promoción.
class _SelectorImagen extends StatelessWidget {
  const _SelectorImagen({
    required this.imagen,
    required this.imagenUrl,
    required this.onElegir,
    required this.onQuitar,
  });

  final Uint8List? imagen;

  /// La ya subida (al editar), si no se eligió otra.
  final String imagenUrl;
  final VoidCallback? onElegir;
  final VoidCallback? onQuitar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tiene = imagen != null || imagenUrl.isNotEmpty;
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Material(
                      shape: CircleBorder(
                        side: BorderSide(
                          color: tiene
                              ? AppColores.primary
                              : palette.borderSubtle,
                          width: tiene ? 4 : 1.5,
                        ),
                      ),
                      color: palette.surface,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onElegir,
                        child: !tiene
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.add_photo_alternate_rounded,
                                    size: 40,
                                    color: AppColores.primary,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Agregar imagen\n(opcional)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : imagen != null
                            ? Image.memory(imagen!, fit: BoxFit.cover)
                            : CachedNetworkImage(
                                imageUrl: imagenUrl,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  if (tiene)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        tooltip: 'Quitar imagen',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: onQuitar,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (tiene)
          TextButton.icon(
            onPressed: onElegir,
            icon: const Icon(Icons.crop_rounded),
            label: const Text('Cambiar o recortar'),
          ),
      ],
    );
  }
}

/// Público de la promoción. Tres tarjetas con el ícono arriba y el texto
/// abajo (el texto se achica antes que cortarse); en un ancho muy angosto
/// se apilan como filas para que "Conductores" siempre se lea completo.
class _SelectorPublico extends StatelessWidget {
  const _SelectorPublico({required this.valor, required this.onCambio});

  final AudienciaPromocion valor;
  final ValueChanged<AudienciaPromocion>? onCambio;

  static const _opciones = [
    (AudienciaPromocion.clientes, Icons.person_rounded, 'Clientes'),
    (AudienciaPromocion.conductores, Icons.local_taxi_rounded, 'Conductores'),
    (AudienciaPromocion.todos, Icons.groups_rounded, 'Todos'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final apilado = c.maxWidth < 300;
        final tarjetas = [
          for (final (a, icono, texto) in _opciones)
            _OpcionPublico(
              icono: icono,
              texto: texto,
              seleccionada: valor == a,
              apilada: apilado,
              onTap: onCambio == null ? null : () => onCambio!(a),
            ),
        ];
        if (apilado) {
          return Column(
            children: [
              for (final t in tarjetas)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: t),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tarjetas.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tarjetas[i]),
            ],
          ],
        );
      },
    );
  }
}

class _OpcionPublico extends StatelessWidget {
  const _OpcionPublico({
    required this.icono,
    required this.texto,
    required this.seleccionada,
    required this.apilada,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final bool seleccionada;
  final bool apilada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = seleccionada ? AppColores.primary : palette.borderSubtle;
    final etiqueta = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        texto,
        maxLines: 1,
        style: TextStyle(
          fontWeight: seleccionada ? FontWeight.w800 : FontWeight.w600,
          color: seleccionada ? AppColores.ink900 : palette.textPrimary,
        ),
      ),
    );
    final iconoW = Icon(
      icono,
      color: seleccionada ? AppColores.ink900 : palette.textSecondary,
    );
    return Semantics(
      selected: seleccionada,
      button: true,
      child: Material(
        // Seleccionada: el naranja principal sólido con contenido oscuro.
        color: seleccionada ? AppColores.primary : palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color, width: seleccionada ? 1.8 : 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // Área táctil mínima de 48 px.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: apilada
                  ? Row(
                      children: [
                        iconoW,
                        const SizedBox(width: 10),
                        Flexible(child: etiqueta),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [iconoW, const SizedBox(height: 4), etiqueta],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
