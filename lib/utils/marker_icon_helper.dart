import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerIconHelper {
  const MarkerIconHelper._();

  /// Punto azul como el indicador nativo "Mi ubicación" de Google Maps
  /// (círculo azul sólido + anillo blanco + sombra suave), en vez del pin
  /// con forma de gota que da `BitmapDescriptor.defaultMarkerWithHue`.
  ///
  /// Con [withHeadingCone] dibuja además el cono de dirección (el "haz" que
  /// se ve en la navegación real de Google Maps) apuntando hacia arriba en
  /// el propio bitmap — al usar este ícono en un `Marker` con `rotation:` y
  /// `anchor: Offset(0.5, 0.5)`, el mapa rota el bitmap completo (punto +
  /// cono) hacia el rumbo real, igual que el puck nativo.
  static Future<BitmapDescriptor> dot({
    double size = 44,
    Color color = const Color(0xFF4285F4),
    bool withHeadingCone = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size * (withHeadingCone ? 0.14 : 0.28);

    if (withHeadingCone) {
      // Cono de dirección: abanico traslúcido apuntando "hacia arriba" en el
      // bitmap (rotation del Marker lo orienta al rumbo real en el mapa).
      // El ancla del Marker queda en el centro exacto del canvas (mismo
      // punto que el dot), así que radius + coneLength no puede pasar de
      // size/2 o la punta del cono queda cortada fuera del bitmap.
      final coneLength = size * 0.28;
      final coneHalfWidth = size * 0.18;
      final tip = Offset(center.dx, center.dy - radius - coneLength);
      final path = Path()
        ..moveTo(center.dx, center.dy - radius * 0.3)
        ..lineTo(tip.dx - coneHalfWidth, tip.dy)
        ..quadraticBezierTo(
          center.dx,
          center.dy - radius - coneLength * 0.55,
          tip.dx + coneHalfWidth,
          tip.dy,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(center.dx, center.dy),
            tip,
            [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
          ),
      );
    }

    canvas.drawCircle(
      center,
      radius + size * 0.05,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, radius + size * 0.05, Paint()..color = Colors.white);
    canvas.drawCircle(center, radius, Paint()..color = color);

    final image = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor?> fromAsset(
    String assetPath, {
    Size size = const Size(52, 52),
    double devicePixelRatio = 1.0,
    bool trimTransparentPadding = true,
    BoxFit fit = BoxFit.contain,
  }) async {
    try {
      int width = (size.width * devicePixelRatio).round();
      int height = (size.height * devicePixelRatio).round();
      if (width < 1) width = 1;
      if (height < 1) height = 1;

      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      Rect srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      if (trimTransparentPadding) {
        final opaqueBounds = await _opaqueBounds(image);
        if (opaqueBounds != null) {
          srcRect = opaqueBounds;
        }
      }

      final outputSize = Size(width.toDouble(), height.toDouble());
      final fitted = applyBoxFit(
        fit,
        Size(srcRect.width, srcRect.height),
        outputSize,
      );
      final dstRect = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & outputSize,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        srcRect,
        dstRect,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final outImage = await picture.toImage(width, height);
      final byteData = await outImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return null;

      // imagePixelRatio = dpr → el marcador se renderiza al tamaño LÓGICO
      // indicado en `size` (consistente en todas las densidades).
      return BitmapDescriptor.bytes(
        byteData.buffer.asUint8List(),
        imagePixelRatio: devicePixelRatio,
      );
    } catch (_) {
      return null;
    }
  }

  /// Renders a Material [IconData] as a map marker. With [circleBackground]
  /// (default) it draws a badge behind the icon — [backgroundColor] +
  /// [borderColor], sized as [backgroundScale] fraction of the full canvas
  /// (1.0 = badge fills the canvas, like the original big-circle look; a
  /// smaller value like 0.62 draws a tight, app-branded badge instead of a
  /// large blank disc). Set `circleBackground` to `false` to render just the
  /// icon's own shape (e.g. the car silhouette) on a transparent background.
  /// [mirrored] flips the icon horizontally — used for southward headings so the
  /// marker never appears upside-down on the map.
  static Future<BitmapDescriptor> fromIcon(
    IconData icon,
    double size,
    Color iconColor, {
    Color borderColor = const Color(0xFFFFCC00),
    Color backgroundColor = Colors.white,
    double backgroundScale = 1.0,
    bool mirrored = false,
    bool circleBackground = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = (size / 2) * backgroundScale;
    final center = Offset(size / 2, size / 2);
    if (circleBackground) {
      if (backgroundScale < 1.0) {
        // Badge compacto: sombra suave para que se distinga del mapa sin
        // necesitar un disco grande.
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawCircle(center, radius, Paint()..color = backgroundColor);
      canvas.drawCircle(
        center,
        radius - size * 0.04,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.07
          ..color = borderColor,
      );
    }
    // Sin el disco de fondo, el ícono puede ocupar casi todo el lienzo y se
    // lee como la silueta del vehículo, no como una insignia circular. Con
    // badge, el ícono escala junto con el tamaño del badge (backgroundScale)
    // para mantenerse proporcional dentro de él.
    final fontFraction = circleBackground ? 0.56 * backgroundScale : 0.86;
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size * fontFraction,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: iconColor,
        ),
      )
      ..layout();
    final iconOffset = Offset((size - tp.width) / 2, (size - tp.height) / 2);
    if (mirrored) {
      canvas.save();
      canvas.translate(size, 0);
      canvas.scale(-1, 1);
      tp.paint(canvas, iconOffset);
      canvas.restore();
    } else {
      tp.paint(canvas, iconOffset);
    }
    final image = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static Future<Rect?> _opaqueBounds(ui.Image image) async {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return null;
    final bytes = raw.buffer.asUint8List();

    final width = image.width;
    final height = image.height;
    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width * 4;
      for (int x = 0; x < width; x++) {
        final alpha = bytes[rowOffset + x * 4 + 3];
        if (alpha > 0) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0 || maxY < 0) return null;
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  static Future<BitmapDescriptor?> fromNetworkPhoto(
    String? imageUrl, {
    int size = 140,
    Color borderColor = Colors.white,
    double borderWidth = 8,
  }) async {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return null;

    try {
      final uri = Uri.parse(url);
      final data = await NetworkAssetBundle(uri).load(uri.toString());
      final bytes = data.buffer.asUint8List();
      return _buildCircularIcon(
        bytes,
        size: size,
        borderColor: borderColor,
        borderWidth: borderWidth,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<BitmapDescriptor?> _buildCircularIcon(
    Uint8List imageBytes, {
    required int size,
    required Color borderColor,
    required double borderWidth,
  }) async {
    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: size,
      targetHeight: size,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = (size / 2) - borderWidth;
    final dstRect = Rect.fromCircle(center: center, radius: radius);
    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(dstRect));
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = borderColor,
    );

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(size, size);
    final byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return null;

    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  }
}
