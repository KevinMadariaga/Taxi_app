import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Muestra la foto recién tomada con opción de voltearla (espejo horizontal),
/// útil cuando la cámara frontal entrega la imagen invertida respecto a lo
/// que el usuario vio en la vista previa. Devuelve el archivo final (volteado
/// o no) o `null` si el usuario cancela.
Future<File?> showFlipPreview(BuildContext context, {required File imageFile}) {
  return Navigator.push<File>(
    context,
    MaterialPageRoute(builder: (_) => FlipPreviewView(imageFile: imageFile)),
  );
}

class FlipPreviewView extends StatefulWidget {
  const FlipPreviewView({super.key, required this.imageFile});

  final File imageFile;

  @override
  State<FlipPreviewView> createState() => _FlipPreviewViewState();
}

class _FlipPreviewViewState extends State<FlipPreviewView> {
  bool _flipped = false;
  bool _saving = false;

  Future<void> _confirm() async {
    if (!_flipped) {
      Navigator.pop(context, widget.imageFile);
      return;
    }

    setState(() => _saving = true);
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        if (mounted) Navigator.pop(context, widget.imageFile);
        return;
      }

      final flipped = img.flipHorizontal(decoded);
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/flipped_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path)
        ..writeAsBytesSync(img.encodeJpg(flipped, quality: 92));

      if (mounted) Navigator.pop(context, file);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ajustar foto de perfil'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: _flipped
                      ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                      : Matrix4.identity(),
                  child: Image.file(widget.imageFile),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                      onPressed: _saving
                          ? null
                          : () => setState(() => _flipped = !_flipped),
                      icon: const Icon(Icons.flip),
                      label: const Text('Voltear'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _confirm,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
