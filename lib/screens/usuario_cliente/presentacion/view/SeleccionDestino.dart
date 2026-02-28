
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:taxi_app/core/app_colores.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/MapaClienteModel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/MapaPreviewView.dart';
import 'InicioClienteView.dart';



class DestinoSeleccionView extends StatefulWidget {
  final LatLng? currentLocation;

  const DestinoSeleccionView({super.key, this.currentLocation});

  @override
  State<DestinoSeleccionView> createState() => _DestinoSeleccionViewState();
}

class _DestinoSeleccionViewState extends State<DestinoSeleccionView> {
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
    // Abrir teclado en el campo destino al entrar en la vista
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_destinoFocus);
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
          title: const Text('Destino'),
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
                  TextField(
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
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'Destino',
                      style: TextStyle(fontSize: labelFontSize, color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
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
                  const SizedBox(height: 8),
                  if (_destinoController.text.trim().isEmpty && _sugerencias.isEmpty) ...[
                    if (widget.currentLocation != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _guardarUbicacionActualComoFavorita,
                          icon: const Icon(Icons.star_border, color: Colors.black87),
                          label: const Text('Guardar ubicación actual'),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _usarUbicacionDesdeTextoCompartido,
                        icon: const Icon(Icons.gps_fixed, color: Colors.black87),
                        label: const Text('Pegar ubicación'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_sugerencias.isNotEmpty)
                    Flexible(
                      child: Card(
                        margin: const EdgeInsets.only(top: 8),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _sugerencias.length,
                          itemBuilder: (context, index) {
                            final s = _sugerencias[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on_outlined, color: Colors.black54),
                              title: Text(s.nombre.isNotEmpty ? s.nombre : s.direccion),
                              subtitle: (s.direccion.isNotEmpty && s.direccion != s.nombre)
                                  ? Text(s.direccion)
                                  : null,
                              onTap: () {
                                FocusScope.of(context).unfocus();
                                if (s.location == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación no disponible')));
                                  return;
                                }
                                _destinoController.text = s.nombre.isNotEmpty ? s.nombre : s.direccion;
                                setState(() => _sugerencias = []);
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => MapaPreviewView(
                                    location: s.location!,
                                    direccion: s.direccion,
                                    origenLocation: widget.currentLocation,
                                    origenDireccion: _origenController.text,
                                  ),
                                ));
                              },
                            );
                          },
                        ),
                      ),
                    ),
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

