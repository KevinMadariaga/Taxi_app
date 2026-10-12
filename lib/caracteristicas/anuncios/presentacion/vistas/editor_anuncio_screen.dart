import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

import '../../datos/repositorios/anuncios_repository_impl.dart';
import '../../dominio/entidades/anuncio.dart';
import '../../dominio/enlaces_anuncio.dart';
import '../../dominio/repositorios/anuncios_repository.dart';
import '../widgets/tarjeta_anuncio.dart';
import '../mensaje_error.dart';

/// Crear o editar un anuncio del carrusel. La imagen se recorta en la
/// proporción de la tarjeta (con zoom y encuadre) y se ve en una vista
/// previa idéntica a la del inicio antes de subirla. El texto y los
/// enlaces (WhatsApp, Instagram) salen al tocar el anuncio.
class EditorAnuncioScreen extends StatefulWidget {
  const EditorAnuncioScreen({
    super.key,
    this.editando,
    this.embebida = false,
    this.alGuardar,
    AnunciosRepository? repositorio,
    Future<Uint8List?> Function(String ruta)? recortar,
  }) : _repositorio = repositorio,
       _recortar = recortar;

  /// Con valor: edita ese anuncio; sin valor: crea uno nuevo.
  final Anuncio? editando;

  /// Dentro de otra pantalla con su propia barra (la pestaña "Crear" de
  /// `AdminAnunciosScreen`): sin Scaffold propio y, al publicar, se limpia
  /// en vez de cerrarse.
  final bool embebida;

  /// Después de guardar con éxito (p. ej. volver a la lista).
  final VoidCallback? alGuardar;
  final AnunciosRepository? _repositorio;

  /// Para tests: reemplaza la pantalla de recorte nativa.
  final Future<Uint8List?> Function(String ruta)? _recortar;

  @override
  State<EditorAnuncioScreen> createState() => _EditorAnuncioScreenState();
}

/// Duración elegida: [_mantener] (solo al editar), [_sinVencimiento] o días.
const int _mantener = -1;
const int _sinVencimiento = 0;
const List<int> _opcionesDias = [1, 3, 7, 15, 30];

class _EditorAnuncioScreenState extends State<EditorAnuncioScreen> {
  late final AnunciosRepository _repo =
      widget._repositorio ?? AnunciosRepositoryImpl();
  final _titulo = TextEditingController();
  final _detalle = TextEditingController();
  final _whatsapp = TextEditingController();
  final _instagram = TextEditingController();

  /// Ruta de la foto elegida sin recortar: permite volver a recortarla.
  String? _original;
  Uint8List? _recortada;
  String _imagenActual = '';
  late int _duracion;
  bool _guardando = false;
  String? _error;

  bool get _editando => widget.editando != null;

  /// Deja el formulario listo para el siguiente anuncio (modo pestaña).
  void _limpiar() {
    for (final c in [_titulo, _detalle, _whatsapp, _instagram]) {
      c.clear();
    }
    setState(() {
      _original = null;
      _recortada = null;
      _imagenActual = '';
      _duracion = _sinVencimiento;
      _guardando = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final a = widget.editando;
    _duracion = a == null ? _sinVencimiento : _mantener;
    if (a != null) {
      _titulo.text = a.titulo;
      _detalle.text = a.detalle;
      _whatsapp.text = a.whatsapp;
      _instagram.text = a.instagram;
      _imagenActual = a.imagenUrl;
    }
  }

  @override
  void dispose() {
    for (final c in [_titulo, _detalle, _whatsapp, _instagram]) {
      c.dispose();
    }
    super.dispose();
  }

  /// La misma pantalla de recorte que la foto de perfil, en 3:2.
  Future<Uint8List?> _recortar(String ruta) async {
    final propio = widget._recortar;
    if (propio != null) return propio(ruta);
    final archivo = await const ImageCropperService().cropAnuncioImage(
      sourcePath: ruta,
    );
    return archivo?.readAsBytes();
  }

  Future<void> _elegirImagen() async {
    final foto = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    if (foto == null || !mounted) return;
    _original = foto.path;
    await _recortarDeNuevo();
  }

  Future<void> _recortarDeNuevo() async {
    final original = _original;
    if (original == null) return;
    try {
      final recortada = await _recortar(original);
      if (recortada != null && mounted) {
        setState(() => _recortada = recortada);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'editor_anuncio: recortar');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el recorte.')),
        );
      }
    }
  }

  String? _errorWhatsApp() {
    final v = _whatsapp.text.trim();
    return v.isEmpty || enlaceWhatsApp(v) != null
        ? null
        : 'Número no válido (ej. 300 123 4567).';
  }

  String? _errorInstagram() {
    final v = _instagram.text.trim();
    return v.isEmpty || enlaceInstagram(v) != null
        ? null
        : 'Usuario no válido (ej. @minegocio).';
  }

  bool get _tieneDetalle => [
    _titulo,
    _detalle,
    _whatsapp,
    _instagram,
  ].any((c) => c.text.trim().isNotEmpty);

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_editando && _recortada == null) {
      setState(() => _error = 'Elige la imagen del anuncio.');
      return;
    }
    if (_errorWhatsApp() != null || _errorInstagram() != null) {
      setState(() => _error = 'Revisa el WhatsApp o el Instagram.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final editando = widget.editando;
      if (editando == null) {
        await _repo.crearAnuncio(
          _recortada!,
          dias: _duracion == _sinVencimiento ? null : _duracion,
          titulo: _titulo.text.trim(),
          detalle: _detalle.text.trim(),
          whatsapp: _whatsapp.text.trim(),
          instagram: _instagram.text.trim(),
        );
      } else {
        await _repo.actualizarAnuncio(
          editando,
          titulo: _titulo.text.trim(),
          detalle: _detalle.text.trim(),
          whatsapp: _whatsapp.text.trim(),
          instagram: _instagram.text.trim(),
          dias: _duracion == _mantener ? null : _duracion,
          nuevaImagen: _recortada,
        );
      }
      if (!mounted) return;
      if (widget.embebida) {
        _limpiar();
        widget.alGuardar?.call();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'editor_anuncio: guardar');
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = mensajeErrorAccion(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Widget? imagen = _recortada != null
        ? Image.memory(_recortada!, fit: BoxFit.cover)
        : _imagenActual.isNotEmpty
        ? CachedNetworkImage(imageUrl: _imagenActual, fit: BoxFit.cover)
        : null;

    final vistaPrevia = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Así se verá en el inicio',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: kProporcionAnuncio,
          child: imagen == null
              ? _SinImagen(onTap: _guardando ? null : _elegirImagen)
              : TarjetaAnuncio(imagen: imagen, conDetalle: _tieneDetalle),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _guardando ? null : _elegirImagen,
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(imagen == null ? 'Elegir imagen' : 'Cambiar imagen'),
            ),
            if (_original != null)
              OutlinedButton.icon(
                onPressed: _guardando ? null : _recortarDeNuevo,
                icon: const Icon(Icons.crop_rounded),
                label: const Text('Ajustar recorte'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Al elegirla puedes moverla, acercarla y girarla para que se vea '
          'bien en la tarjeta.',
          style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
        ),
      ],
    );

    InputDecoration deco(String etiqueta, {IconData? icono, String? error}) =>
        InputDecoration(
          labelText: etiqueta,
          prefixIcon: icono == null ? null : Icon(icono),
          errorText: error,
        );

    final formulario = <Widget>[
      Text(
        'Detalle (opcional)',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Si lo llenas, el anuncio muestra "Ver detalle" y al tocarlo se '
        'abre con este texto y los botones de contacto.',
        style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _titulo,
        maxLength: 60,
        maxLines: null,
        enabled: !_guardando,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: deco('Nombre del negocio'),
      ),
      TextField(
        controller: _detalle,
        maxLength: 300,
        // Crece con el texto: la pantalla se desplaza, no el campo.
        minLines: 2,
        maxLines: null,
        textInputAction: TextInputAction.done,
        enabled: !_guardando,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        onChanged: (_) => setState(() {}),
        decoration: deco('Descripción'),
      ),
      const SizedBox(height: 4),
      TextField(
        controller: _whatsapp,
        enabled: !_guardando,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')),
        ],
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
        decoration: deco(
          'WhatsApp',
          icono: Icons.chat_rounded,
          error: _errorWhatsApp(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _instagram,
        enabled: !_guardando,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        decoration: deco(
          'Instagram (@usuario)',
          icono: Icons.camera_alt_rounded,
          error: _errorInstagram(),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        '¿Cuánto tiempo se muestra?',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in [
            if (_editando) _mantener,
            _sinVencimiento,
            ..._opcionesDias,
          ])
            ChipSeleccion(
              texto: switch (d) {
                _mantener => 'Mantener',
                _sinVencimiento => 'Sin vencimiento',
                1 => '1 día',
                _ => '$d días',
              },
              seleccionado: _duracion == d,
              onSeleccionar: _guardando
                  ? null
                  : () => setState(() => _duracion = d),
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
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Icon(_editando ? Icons.save_rounded : Icons.publish_rounded),
          label: Text(
            _guardando
                ? 'Guardando...'
                : (_editando ? 'Guardar cambios' : 'Publicar anuncio'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];

    final cuerpo = SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          final ancho = c.maxWidth >= 840;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.all(ancho ? 24 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: ancho ? 1100 : 640),
                child: ancho
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: vistaPrevia),
                          const SizedBox(width: 32),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: formulario,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          vistaPrevia,
                          const SizedBox(height: 22),
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
        titulo: _editando ? 'Editar anuncio' : 'Nuevo anuncio',
      ),
      body: cuerpo,
    );
  }
}

class _SinImagen extends StatelessWidget {
  const _SinImagen({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.borderSubtle, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_photo_alternate_rounded,
              size: 40,
              color: AppColores.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Toca para elegir la imagen',
              style: TextStyle(color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
