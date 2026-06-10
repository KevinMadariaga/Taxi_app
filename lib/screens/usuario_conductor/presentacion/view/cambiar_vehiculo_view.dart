import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';
import 'package:taxi_app/widgets/boton.dart';

/// Permite al conductor gestionar DOS vehículos (carro y moto). Cada tipo
/// guarda su propia foto y placa en `usuarios/{uid}.vehiculos.{tipo}`. Al
/// guardar, el tipo seleccionado queda como vehículo activo
/// (`tipoVehiculo`/`fotoVehiculo`/`placa`).
class CambiarVehiculoView extends StatefulWidget {
  const CambiarVehiculoView({super.key});

  @override
  State<CambiarVehiculoView> createState() => _CambiarVehiculoViewState();
}

class _CambiarVehiculoViewState extends State<CambiarVehiculoView> {
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _cropper = const ImageCropperService();

  VehicleType _tipo = VehicleType.carro;

  // Estado por tipo de vehículo (carro / moto).
  final Map<VehicleType, TextEditingController> _placas = {
    VehicleType.carro: TextEditingController(),
    VehicleType.moto: TextEditingController(),
  };
  final Map<VehicleType, XFile?> _fotosNuevas = {
    VehicleType.carro: null,
    VehicleType.moto: null,
  };
  final Map<VehicleType, String> _fotosUrl = {
    VehicleType.carro: '',
    VehicleType.moto: '',
  };

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null && mounted) {
        final tipoActivo = (data['tipoVehiculo'] ?? '').toString().toLowerCase();
        if (tipoActivo == 'moto') _tipo = VehicleType.moto;

        final vehiculos = data['vehiculos'];
        final Map<String, dynamic> mapa = vehiculos is Map
            ? Map<String, dynamic>.from(vehiculos)
            : <String, dynamic>{};

        for (final t in VehicleType.values) {
          final v = mapa[t.firestoreKey];
          if (v is Map) {
            _fotosUrl[t] = (v['foto'] ?? '').toString();
            _placas[t]!.text = (v['placa'] ?? '').toString();
          }
        }

        // Sembrar el tipo activo desde campos legacy si no había mapa.
        final activeKey = tipoActivo == 'moto' ? 'moto' : 'carro';
        if (mapa[activeKey] is! Map) {
          final t = tipoActivo == 'moto'
              ? VehicleType.moto
              : VehicleType.carro;
          final legacyFoto = (data['fotoVehiculo'] ?? '').toString();
          final legacyPlaca = (data['placa'] ?? '').toString();
          if (legacyFoto.isNotEmpty) _fotosUrl[t] = legacyFoto;
          if (legacyPlaca.isNotEmpty && _placas[t]!.text.isEmpty) {
            _placas[t]!.text = legacyPlaca;
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    for (final c in _placas.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final cropped = await _cropper.cropVehicleImage(sourcePath: picked.path);
      if (cropped == null) return;
      setState(() => _fotosNuevas[_tipo] = XFile(cropped.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error seleccionando imagen: $e')),
      );
    }
  }

  Future<String> _subirImagen(XFile file, String uid) async {
    final path =
        'usuarios/$uid/fotoVehiculo_${_tipo.firestoreKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = fb_storage.FirebaseStorage.instance.ref().child(path);
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final placa = _placas[_tipo]!.text.trim();
    final tieneFoto =
        _fotosNuevas[_tipo] != null || _fotosUrl[_tipo]!.isNotEmpty;
    if (!tieneFoto) {
      _mostrarError('Agrega la foto de tu ${_tipo.label.toLowerCase()}.');
      return;
    }
    if (placa.isEmpty) {
      _mostrarError('Ingresa la placa de tu ${_tipo.label.toLowerCase()}.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotosNuevas[_tipo] != null
          ? await _subirImagen(_fotosNuevas[_tipo]!, uid)
          : _fotosUrl[_tipo]!;
      final placaUp = placa.toUpperCase();

      final data = <String, dynamic>{
        // Solo se actualiza la sub-clave del tipo (merge conserva el otro).
        'vehiculos': {
          _tipo.firestoreKey: {'foto': fotoUrl, 'placa': placaUp},
        },
        // El tipo seleccionado queda como vehículo activo.
        'tipoVehiculo': _tipo.firestoreKey,
        'fotoVehiculo': fotoUrl,
        'placa': placaUp,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vehículo activo: ${_tipo.label}.'),
          backgroundColor: AppColores.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarError('No se pudo guardar: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColores.error),
    );
  }

  Widget _tipoCard(VehicleType tipo, IconData icon) {
    final sel = _tipo == tipo;
    final tieneDatos = _fotosUrl[tipo]!.isNotEmpty || _fotosNuevas[tipo] != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _tipo = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: sel
              ? AppColores.primary.withValues(alpha: 0.12)
              : AppColores.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? AppColores.primary : AppColores.grey300,
            width: sel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: sel ? const Color(0xFFB38F00) : AppColores.grey600,
            ),
            const SizedBox(height: 8),
            Text(
              tipo.label,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                fontSize: 15,
                color: AppColores.textPrimary,
              ),
            ),
            if (tieneDatos)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Registrado',
                  style: TextStyle(fontSize: 11, color: AppColores.success),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fotoNueva = _fotosNuevas[_tipo];
    final fotoUrl = _fotosUrl[_tipo]!;

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Cambiar de vehículo'),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: AppColores.primary),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Selecciona el vehículo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _tipoCard(
                            VehicleType.carro,
                            Icons.directions_car_filled_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _tipoCard(
                            VehicleType.moto,
                            Icons.two_wheeler_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Foto del ${_tipo.label.toLowerCase()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 170,
                              width: double.infinity,
                              color: AppColores.grey200,
                              child: fotoNueva != null
                                  ? Image.file(
                                      File(fotoNueva.path),
                                      fit: BoxFit.cover,
                                    )
                                  : fotoUrl.isNotEmpty
                                      ? Image.network(fotoUrl, fit: BoxFit.cover)
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              _tipo == VehicleType.moto
                                                  ? Icons.two_wheeler_rounded
                                                  : Icons.directions_car,
                                              size: 40,
                                              color: Colors.black54,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Agregar foto del ${_tipo.label.toLowerCase()}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColores.buttonPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: AppColores.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _placas[_tipo],
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Placa del ${_tipo.label.toLowerCase()}',
                        prefixIcon: const Icon(Icons.confirmation_number),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 28),
                    CustomButton(
                      text: _guardando
                          ? 'Guardando...'
                          : 'Usar ${_tipo.label} y guardar',
                      isLoading: _guardando,
                      onPressed: _guardando ? null : _guardar,
                      height: 50,
                      fontSize: 16,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
