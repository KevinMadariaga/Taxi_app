
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/app_colores.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/MapaClienteModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/DetailsSolicitud.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/MapaPreviewView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/SeleccionaUbicacionEnMapaView.dart';
import 'InicioClienteView.dart';



class DestinoSeleccionView extends StatefulWidget {
  final LatLng? currentLocation;

  const DestinoSeleccionView({super.key, this.currentLocation});

  @override
  State<DestinoSeleccionView> createState() => _DestinoSeleccionViewState();
}

class _DestinoSeleccionViewState extends State<DestinoSeleccionView> {
    Future<void> _seleccionarYGuardarUbicacion(String tipo) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (tipo == 'Favorito') {
        // Mostrar desplegable de favoritos guardados y opción de agregar
        final snapshot = await FirebaseFirestore.instance
            .collection('ubicaciones')
            .where('userId', isEqualTo: user.uid)
            .where('tipo', isEqualTo: 'Favorito')
            .get();
        final favoritos = snapshot.docs;
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) {
            return Padding(
              padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Favoritos guardados', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  ...favoritos.map((doc) {
                    final data = doc.data();
                    final geopoint = data['ubicacion'] as GeoPoint?;
                    final nombre = (data['nombre'] ?? 'Favorito') as String;
                    if (geopoint == null) return const SizedBox();
                    return ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(nombre),
                      subtitle: Text(data['direccion'] ?? ''),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MapPreview(
                              origen: LocationModel(
                                position: widget.currentLocation ?? LatLng(0, 0),
                                title: 'Tu ubicación',
                              ),
                              destino: LocationModel(
                                position: LatLng(geopoint.latitude, geopoint.longitude),
                                title: nombre,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add, color: Colors.black54),
                    title: const Text('Agregar nuevo favorito'),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final LatLng ubicacionInicial = widget.currentLocation ?? LatLng(0, 0);
                      final resultado = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SeleccionaUbicacionEnMapaView(
                            ubicacionInicial: ubicacionInicial,
                            titulo: 'Selecciona ubicación de Favorito',
                          ),
                        ),
                      );
                      if (resultado is LatLng) {
                        // Solicitar nombre personalizado
                        String nombreFavorito = '';
                        await showDialog(
                          context: context,
                          builder: (dctx) {
                            return AlertDialog(
                              title: const Text('Nombre del favorito'),
                              content: TextField(
                                autofocus: true,
                                decoration: const InputDecoration(hintText: 'Ej. Colegio, Gimnasio'),
                                onChanged: (value) => nombreFavorito = value,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(dctx).pop(),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(dctx).pop(),
                                  child: const Text('Guardar'),
                                ),
                              ],
                            );
                          },
                        );
                        if (nombreFavorito.trim().isEmpty) nombreFavorito = 'Favorito';
                        await _guardarUbicacionPersonalizada('Favorito', resultado, nombreFavorito);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
        return;
      }
      // Casa y Trabajo: lógica anterior
      if (tipo == 'Casa' || tipo == 'Trabajo') {
        final snapshot = await FirebaseFirestore.instance
            .collection('ubicaciones')
            .where('userId', isEqualTo: user.uid)
            .where('tipo', isEqualTo: tipo)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.first.data();
          final geopoint = data['ubicacion'] as GeoPoint?;
          final nombre = (data['nombre'] ?? tipo) as String;
          if (geopoint != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MapPreview(
                  origen: LocationModel(
                    position: widget.currentLocation ?? LatLng(0, 0),
                    title: 'Tu ubicación',
                  ),
                  destino: LocationModel(
                    position: LatLng(geopoint.latitude, geopoint.longitude),
                    title: nombre,
                  ),
                ),
              ),
            );
            return;
          }
        }
      }
      // Si no existe, seleccionar y guardar como antes
      final LatLng ubicacionInicial = widget.currentLocation ?? LatLng(0, 0);
      final resultado = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SeleccionaUbicacionEnMapaView(
            ubicacionInicial: ubicacionInicial,
            titulo: 'Selecciona ubicación de $tipo',
          ),
        ),
      );
      if (resultado is LatLng) {
        await _guardarUbicacionPersonalizada(tipo, resultado, tipo);
      }
    }

    Future<void> _guardarUbicacionPersonalizada(String tipo, LatLng loc, [String? nombrePersonalizado]) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar: usuario no autenticado')),
        );
        return;
      }
      String direccion = '';
      try {
        final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          direccion = [p.street, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => (s ?? '').isNotEmpty).join(', ');
        }
      } catch (_) {}
      if (direccion.isEmpty) {
        direccion = '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
      }
      await FirebaseFirestore.instance.collection('ubicaciones').add({
        'userId': user.uid,
        'nombre': nombrePersonalizado ?? tipo,
        'direccion': direccion,
        'ubicacion': GeoPoint(loc.latitude, loc.longitude),
        'createdAt': FieldValue.serverTimestamp(),
        'tipo': tipo,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ubicación guardada como "${nombrePersonalizado ?? tipo}"')),
      );
    }
  final TextEditingController _origenController = TextEditingController();
  final TextEditingController _destinoController = TextEditingController();
  final FocusNode _origenFocus = FocusNode();
  final FocusNode _destinoFocus = FocusNode();
  List<UbicacionResultado> _sugerencias = [];

  @override
  void initState() {
    super.initState();
    _destinoFocus.addListener(() => setState(() {}));
    _origenFocus.addListener(() => setState(() {}));
    // Si se recibió ubicación actual, mostrarla en el campo Origen
    if (widget.currentLocation != null) {
      _setOrigenDesdeCoordenadas(widget.currentLocation!);
    }
    // Abrir teclado en el campo destino al entrar en la vista y seleccionar todo el texto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_destinoFocus);
      _destinoController.selection = TextSelection(baseOffset: 0, extentOffset: _destinoController.text.length);
    });
  }

  Future<void> _setOrigenDesdeCoordenadas(LatLng coord) async {
    try {
      final placemarks = await placemarkFromCoordinates(coord.latitude, coord.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final direccion = [p.street, p.subLocality, p.locality, p.administrativeArea]
            .where((s) => s != null && s.isNotEmpty)
            .join(', ');
        setState(() {
          _origenController.text = direccion.isNotEmpty
              ? direccion
              : '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      // Si falla reverse geocoding, mostrar coordenadas
      setState(() {
        _origenController.text = '${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}';
      });
    }
  }

  @override
  void dispose() {
    _origenController.dispose();
    _destinoController.dispose();
    _destinoFocus.dispose();
    _origenFocus.dispose();
    super.dispose();
  }

  /// Extrae un LatLng del texto pegado.
  /// Primero busca pares lat,lng en el propio texto.
  /// Si no encuentra, intenta resolver si hay un link (por ejemplo maps.app.goo.gl)
  /// siguiendo el redirect una vez y buscando coordenadas en el destino.
  Future<LatLng?> _extraerLatLngDesdeTexto(String text) async {
    // 1) Buscar coordenadas directas en el texto
    final reg = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
    final matches = reg.allMatches(text).toList();
    if (matches.isNotEmpty) {
      final selected = matches.length >= 2 ? matches[1] : matches[0];
      final lat = double.tryParse(selected.group(1) ?? '');
      final lng = double.tryParse(selected.group(2) ?? '');
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    // 2) Buscar coordenadas en Google Maps links con '@lat,lng'
    final urlMatch = RegExp(r'(https?://[^\s]+)').firstMatch(text);
    final rawUrl = (urlMatch?.group(1) ?? text).trim();
    if (rawUrl.isNotEmpty && rawUrl.contains('google.com/maps')) {
      // Buscar el patrón @lat,lng en el link
      final atReg = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)(?:,|z)');
      final atMatches = atReg.allMatches(rawUrl).toList();
      if (atMatches.isNotEmpty) {
        // Si es un link de /place/, tomar la primera ocurrencia
        if (rawUrl.contains('/place/')) {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
        // Si es un link de /dir/, tomar la segunda ocurrencia si existe
        else if (rawUrl.contains('/dir/')) {
          final m = atMatches.length > 1 ? atMatches[1] : atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
        // Si no se puede identificar, tomar la primera
        else {
          final m = atMatches[0];
          final lat = double.tryParse(m.group(1) ?? '');
          final lng = double.tryParse(m.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }
      }
    }

    // 2) Si no hay coords directas, intentar con un URL (short link de Google Maps, etc.)
    try {
      final urlMatch = RegExp(r'(https?://[^\s]+)').firstMatch(text);
      final rawUrl = (urlMatch?.group(1) ?? text).trim();
      if (rawUrl.isEmpty) return null;

      Uri uri;
      try {
        uri = Uri.parse(rawUrl);
      } catch (_) {
        return null;
      }
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$rawUrl');
      }

      final client = http.Client();
      try {
        // Si es un short link de Google Maps, seguir el redirect
        bool isShortGoogleMaps = uri.host.contains('maps.app.goo.gl');
        String target = '';
        if (isShortGoogleMaps) {
          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..maxRedirects = 1
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';

          final resp = await client.send(req).timeout(const Duration(seconds: 6));
          // El header Location debe contener el link largo
          target = resp.headers['location'] ?? '';
          if (target.isEmpty) {
            // Si no hay redirect explícito, intentar con el cuerpo como fallback
            target = await resp.stream.bytesToString();
          }
        } else {
          // Si no es short link, usar el propio URL
          target = uri.toString();
        }
        if (target.isEmpty) return null;

        // Buscar coordenadas en el link largo o en el contenido
        final targetMatches = reg.allMatches(target).toList();
        if (targetMatches.isNotEmpty) {
          final selected = targetMatches.length >= 2
              ? targetMatches[1]
              : targetMatches[0];
          final lat = double.tryParse(selected.group(1) ?? '');
          final lng = double.tryParse(selected.group(2) ?? '');
          if (lat != null && lng != null) {
            return LatLng(lat, lng);
          }
        }

        // Si no se encontró en el link, intentar obtener el HTML y buscar coordenadas
        if (isShortGoogleMaps && target.isNotEmpty) {
          try {
            final resp2 = await client.get(Uri.parse(target)).timeout(const Duration(seconds: 6));
            final html = resp2.body;
            final htmlMatches = reg.allMatches(html).toList();
            if (htmlMatches.isNotEmpty) {
              final selected = htmlMatches.length >= 2 ? htmlMatches[1] : htmlMatches[0];
              final lat = double.tryParse(selected.group(1) ?? '');
              final lng = double.tryParse(selected.group(2) ?? '');
              if (lat != null && lng != null) {
                return LatLng(lat, lng);
              }
            }
          } catch (_) {}
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _usarUbicacionDesdeTextoCompartido() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      String text = data?.text?.trim() ?? '';
      // Si el texto está cortado, intenta buscar el primer link completo
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
      if (urlMatch != null) {
        // Si el texto termina justo después del link, probablemente está completo
        // Si hay más texto después, intenta tomar solo el link
        text = urlMatch.group(0)!;
      }
      if (text.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay texto en el portapapeles')),
        );
        return;
      }

      // Si es un shortlink de maps.app.goo.gl, seguir el redirect para obtener el link largo
      String linkParaExtraer = text;
      if (text.contains('maps.app.goo.gl')) {
        try {
          final uri = Uri.parse(text);
          final client = http.Client();
          final req = http.Request('GET', uri)
            ..followRedirects = false
            ..maxRedirects = 1
            ..headers['User-Agent'] = 'Mozilla/5.0 (Flutter TaxiApp; +https://example.com)';
          final resp = await client.send(req).timeout(const Duration(seconds: 6));
          final redirected = resp.headers['location'] ?? '';
          if (redirected.isNotEmpty) linkParaExtraer = redirected;
          client.close();
        } catch (_) {}
      }

      // Mostrar lat/lng y el link largo si se puede extraer
      final coords = extraerLatLng(linkParaExtraer);
      if (coords != null) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Coordenadas encontradas'),
            content: Text('Latitud: ${coords['latitud']},\nLongitud: ${coords['longitud']}\n\nLink completo:\n$linkParaExtraer'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }


      // Intentar extraer coordenadas desde el texto o resolviendo el link
      final destinoLatLng = await _extraerLatLngDesdeTexto(text);
      if (destinoLatLng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron coordenadas en el texto compartido')),
        );
        return;
      }
      // Usar una etiqueta genérica basada en el texto compartido
      setState(() {
        _destinoController.text = 'Ubicación compartida';
        _sugerencias = [];
      });

      if (!mounted) return;
      FocusScope.of(context).unfocus();

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MapaPreviewView(
            location: destinoLatLng,
            direccion: _destinoController.text,
            origenLocation: widget.currentLocation,
            origenDireccion: _origenController.text,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al leer la ubicación compartida')),
      );
    }
  }

  Future<void> _guardarUbicacionActualComoFavorita() async {
    final loc = widget.currentLocation;
    if (loc == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar: usuario no autenticado')),
      );
      return;
    }

    String etiqueta = '';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Guardar ubicación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elige un nombre para esta ubicación:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Casa'),
                    onPressed: () {
                      etiqueta = 'Casa';
                      Navigator.of(ctx).pop();
                    },
                  ),
                  ActionChip(
                    label: const Text('Trabajo'),
                    onPressed: () {
                      etiqueta = 'Trabajo';
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Otro nombre (opcional):'),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Ej. Colegio de los niños',
                ),
                onChanged: (value) {
                  etiqueta = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                etiqueta = etiqueta.trim();
                Navigator.of(ctx).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (etiqueta.isEmpty) return;

    try {
      // Obtener una dirección legible para guardar junto con el nombre
      String direccion = '';
      try {
        final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          direccion = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => (s ?? '').isNotEmpty).join(', ');
        }
      } catch (_) {}

      // Fallback: usar coordenadas si no se pudo obtener dirección
      if (direccion.isEmpty) {
        direccion = '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}';
      }

      await FirebaseFirestore.instance.collection('ubicaciones').add({
        'userId': user.uid,
        'nombre': etiqueta,
        'direccion': direccion,
        'ubicacion': GeoPoint(loc.latitude, loc.longitude),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ubicación guardada como "$etiqueta"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la ubicación')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double screenW = size.width;
    final bool isTablet = screenW >= 1000;
    // Fuente responsiva para TextField
    final double textFieldFontSize = (screenW / 390 * 16).clamp(14, 22);
    final double labelFontSize = (screenW / 390 * 12).clamp(11, 16);
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const InicioClienteView()));
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const InicioClienteView()));
            },
          ),
          title: const Text('¿A donde vamos?', style: TextStyle(color: Colors.black87)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
        ),
        body: SafeArea(
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 64.0 : 16.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'Origen',
                      style: TextStyle(fontSize: labelFontSize, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _origenController,
                          focusNode: _origenFocus,
                          readOnly: true,
                          style: TextStyle(fontSize: textFieldFontSize),
                          decoration: InputDecoration(
                            hintText: 'Selecciona o ajusta moviendo el mapa',
                            hintStyle: TextStyle(fontSize: textFieldFontSize * 0.95),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: const Icon(
                              Icons.place,
                              color: Colors.black54,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.star_border, color: Colors.amber),
                              tooltip: 'Guardar ubicación',
                              onPressed: _guardarUbicacionActualComoFavorita,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'Destino',
                      style: TextStyle(fontSize: labelFontSize, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _destinoController,
                          focusNode: _destinoFocus,
                          autofocus: true,
                          style: TextStyle(fontSize: textFieldFontSize),
                          decoration: InputDecoration(
                            hintText: 'Seleccione un destino',
                            hintStyle: TextStyle(fontSize: textFieldFontSize * 0.95),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: const Icon(
                              Icons.place,
                              color: Colors.black54,
                            ),
                            suffixIcon: _destinoFocus.hasFocus
                                ? IconButton(
                                    tooltip: 'Borrar',
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.black54,
                                    ),
                                    onPressed: () {
                                      _destinoController.clear();
                                      setState(() {
                                        _sugerencias = [];
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColores.buttonPrimary,
                                width: 2.5,
                              ),
                            ),
                          ),
                          onChanged: (value) async {
                            if (value.trim().isEmpty) {
                              setState(() => _sugerencias = []);
                              return;
                            }
                            final results = await buscarUbicacionesHelper(value);
                            setState(() => _sugerencias = results);
                          },
                        ),
                        
                      ),
                      
                    ],
                    
                  ),
                  const SizedBox(height: 8),
                  if (_sugerencias.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _sugerencias.length + 2,
                        itemBuilder: (context, index) {
                          if (index < _sugerencias.length) {
                            final s = _sugerencias[index];
                            return InkWell(
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MapaPreviewView(
                                      location: s.location ?? LatLng(0, 0),
                                      direccion: s.direccion,
                                      origenLocation: widget.currentLocation,
                                      origenDireccion: _origenController.text,
                                    ),
                                  ),
                                );
                              },
                              child: Card(
                                margin: EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: MediaQuery.of(context).size.width * 0.02,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width * 0.025),
                                  side: BorderSide(color: Colors.amber.shade200, width: 1.0),
                                ),
                                elevation: 1.5,
                                child: Container(
                                  constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.width * 0.11),
                                  padding: EdgeInsets.symmetric(
                                    vertical: MediaQuery.of(context).size.width * 0.015,
                                    horizontal: MediaQuery.of(context).size.width * 0.03,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.location_on_outlined, color: Colors.black54, size: MediaQuery.of(context).size.width * 0.055),
                                      SizedBox(width: MediaQuery.of(context).size.width * 0.02),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.nombre.isNotEmpty ? s.nombre : s.direccion,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: MediaQuery.of(context).size.width * 0.036,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (s.direccion.isNotEmpty && s.direccion != s.nombre)
                                              Padding(
                                                padding: EdgeInsets.only(top: MediaQuery.of(context).size.width * 0.005),
                                                child: Text(
                                                  s.direccion,
                                                  style: TextStyle(
                                                    fontSize: MediaQuery.of(context).size.width * 0.031,
                                                    color: Colors.black54,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else if (index == _sugerencias.length) {
                            return Column(
                              children: [
                                const Divider(thickness: 1, color: Colors.grey),
                              ],
                            );
                          } else {
                            // Último elemento: botón 'Pegar ubicación' con padding inferior igual al teclado
                            final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
                            return Padding(
                              padding: EdgeInsets.fromLTRB(16.0, 8.0, 16.0, bottomPadding > 0 ? bottomPadding : 16.0),
                              child: Row(
                                children: [
                                  Icon(Icons.gps_fixed, color: Colors.black87),
                                  SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _usarUbicacionDesdeTextoCompartido,
                                    child: Text('Pegar ubicación', style: TextStyle(fontSize: 16, color: Colors.black87)),
                                  ),
                                  Spacer(),
                                ],
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  if (_sugerencias.isEmpty)
                    SizedBox(height: screenW * 0.04),
                  if (_sugerencias.isEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GestureDetector(
                          onTap: () => _seleccionarYGuardarUbicacion('Casa'),
                          child: Row(
                            children: [
                              Icon(Icons.home, color: Colors.amber, size: 28),
                              SizedBox(width: 6),
                              Text('Casa', style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500)),
                              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _seleccionarYGuardarUbicacion('Trabajo'),
                          child: Row(
                            children: [
                              Icon(Icons.work, color: Colors.amber, size: 28),
                              SizedBox(width: 6),
                              Text('Trabajo', style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500)),
                              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _seleccionarYGuardarUbicacion('Favorito'),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 28),
                              SizedBox(width: 6),
                              Text('Favoritos', style: TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500)),
                              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  // SizedBox(height: 16),
                  // Divider(thickness: 1, color: Colors.grey[300]),
                  // const SizedBox(height: 8),
                  // // Sección de acciones debajo del divider
                  // Row(
                  //   children: [
                  //     Icon(Icons.add, color: Colors.black54),
                  //     SizedBox(width: 8),
                  //     Text('Agregar ubicación', style: TextStyle(fontSize: 16, color: Colors.black87)),
                  //     Spacer(),
                  //   ],
                  // ),
                  // SizedBox(height: 12),
                  // Row(
                  //   children: [
                  //     Icon(Icons.edit, color: Colors.black54),
                  //     SizedBox(width: 8),
                  //     Text('Editar ubicación', style: TextStyle(fontSize: 16, color: Colors.black87)),
                  //     Spacer(),
                  //   ],
                  // ),
                  // SizedBox(height: 12),
                  // Row(
                  //   children: [
                  //     Icon(Icons.notes, color: Colors.black54),
                  //     SizedBox(width: 8),
                  //     Text('Otros comentarios', style: TextStyle(fontSize: 16, color: Colors.black87)),
                  //     Spacer(),
                  //   ],
                  // ),
                  // SizedBox(height: 12),
                  // Row(
                  //   children: [
                  //     Icon(Icons.gps_fixed, color: Colors.black87),
                  //     SizedBox(width: 8),
                  //     TextButton(
                  //       onPressed: _usarUbicacionDesdeTextoCompartido,
                  //       child: Text('Pegar ubicación', style: TextStyle(fontSize: 16, color: Colors.black87)),
                  //     ),
                  //     Spacer(),
                  //   ],
                  // ),
                  

                ],
              ),
            ),
          ),
        ),
      ),
    );
  
  }
}
  /// Extrae latitud y longitud de un link de Google Maps con @lat,lng
  Map<String, double>? extraerLatLng(String url) {
    final RegExp regex = RegExp(r'@([-0-9.]+),([-0-9.]+)');
    final match = regex.firstMatch(url);
    if (match != null) {
      final double lat = double.parse(match.group(1)!);
      final double lng = double.parse(match.group(2)!);
      return {
        'latitud': lat,
        'longitud': lng,
      };
    }
    return null;
  }

Future<List<UbicacionResultado>> buscarUbicacionesHelper(String query) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return [];
  }

  final snapshot = await FirebaseFirestore.instance
      .collection('ubicaciones')
      .get();
  final normalizado = query.toLowerCase();
  return snapshot.docs
      .where((doc) {
        final data = doc.data();
        final nombre = (data['nombre'] ?? '') as String;
      final direccion = (data['direccion'] ?? '') as String;
        final ownerId = data['userId'] as String?;

        // Si tiene ownerId, solo mostrar si pertenece al usuario actual
        if (ownerId != null && ownerId.isNotEmpty && ownerId != user.uid) {
          return false;
        }

        final textoBusqueda = (nombre + ' ' + direccion).toLowerCase();
        return textoBusqueda.contains(normalizado);
      })
      .map((doc) {
        final data = doc.data();
        final geopoint = data['ubicacion'] as GeoPoint;
        final nombre = (data['nombre'] ?? '') as String;
        final direccion = (data['direccion'] ?? '') as String;
        return UbicacionResultado(
          location: LatLng(geopoint.latitude, geopoint.longitude),
          nombre: nombre,
          direccion: direccion.isNotEmpty ? direccion : nombre,
        );
      })
      .toList();
}

