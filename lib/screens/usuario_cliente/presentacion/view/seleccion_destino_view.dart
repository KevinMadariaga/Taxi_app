import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:geocoding/geocoding.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/mapa_cliente_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/mapa_seleccion_destino_view.dart';
import 'inicio_cliente_view.dart';

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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Al pulsar el botón físico de retroceso, navegar a InicioClienteView
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
          child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'Origen',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _origenController,
                focusNode: _origenFocus,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Selecciona o ajusta moviendo el mapa',
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: const Icon(
                    Icons.place,
                    color: Colors.black54,
                  ),
                  // Campo sólo lectura: quitar el sufijo de borrar
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'Destino',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _destinoController,
                focusNode: _destinoFocus,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Seleccione un destino',
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
                            // Aquí puedes invocar la lógica para limpiar resultados
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
                          title: Text(s.direccion),
                          onTap: () {
                            // Cerrar teclado al seleccionar una ubicación
                            FocusScope.of(context).unfocus();
                            if (s.location == null) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación no disponible')));
                              return;
                            }
                            _destinoController.text = s.direccion;
                            setState(() => _sugerencias = []);
                            // Navegar a la vista de mapa mostrando la ubicación seleccionada
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
    );
  }
}

Future<List<UbicacionResultado>> buscarUbicacionesHelper(String query) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('ubicaciones')
      .get();
  final normalizado = query.toLowerCase();
  return snapshot.docs
      .where(
        (doc) => (doc['nombre'] as String).toLowerCase().contains(normalizado),
      )
      .map((doc) {
        final geopoint = doc['ubicacion'];
        return UbicacionResultado(
          location: LatLng(geopoint.latitude, geopoint.longitude),
          direccion: doc['nombre'],
        );
      })
      .toList();
}

