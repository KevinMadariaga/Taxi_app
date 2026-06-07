import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/widgets/boton.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';

/// Pantalla para que un cliente complete su registro como conductor:
/// foto de perfil, foto del vehículo y placa. Al guardar, sube las imágenes
/// a Storage, persiste los datos en `usuarios/{uid}` y navega a [InicioConductor]
/// mostrando el modal de bienvenida.
class CompletarRegistroConductorView extends StatefulWidget {
  const CompletarRegistroConductorView({super.key});

  @override
  State<CompletarRegistroConductorView> createState() =>
      _CompletarRegistroConductorViewState();
}

class _CompletarRegistroConductorViewState
    extends State<CompletarRegistroConductorView> {
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _cropper = const ImageCropperService();
  final TextEditingController _placaController = TextEditingController();

  XFile? _fotoPerfil;
  XFile? _fotoVehiculo;
  String? _fotoExistenteUrl;
  String? _fotoVehiculoExistenteUrl;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatosCliente();
  }

  Future<void> _cargarDatosCliente() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;
      setState(() {
        _fotoExistenteUrl =
            (data['foto'] ?? data['fotoUrl'] ?? '').toString();
        _fotoVehiculoExistenteUrl = (data['fotoVehiculo'] ?? '').toString();
        final placa = (data['placa'] ?? '').toString();
        if (placa.isNotEmpty) _placaController.text = placa;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _placaController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool esVehiculo}) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;

      // Abrir editor para recortar/mover la foto (mismo flujo que registro cliente).
      final cropped = esVehiculo
          ? await _cropper.cropVehicleImage(sourcePath: picked.path)
          : await _cropper.cropProfileImage(sourcePath: picked.path);
      if (cropped == null) return; // canceló el ajuste

      setState(() {
        final xf = XFile(cropped.path);
        if (esVehiculo) {
          _fotoVehiculo = xf;
        } else {
          _fotoPerfil = xf;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error seleccionando imagen: $e')),
      );
    }
  }

  Future<String> _subirImagen(XFile file, String campo, String uid) async {
    final path =
        'usuarios/$uid/${campo}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = fb_storage.FirebaseStorage.instance.ref().child(path);
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final placa = _placaController.text.trim();
    final tieneFotoPerfil = _fotoPerfil != null ||
        (_fotoExistenteUrl != null && _fotoExistenteUrl!.isNotEmpty);
    if (!tieneFotoPerfil) {
      _mostrarError('Agrega tu foto de perfil.');
      return;
    }
    final tieneFotoVehiculo = _fotoVehiculo != null ||
        (_fotoVehiculoExistenteUrl != null &&
            _fotoVehiculoExistenteUrl!.isNotEmpty);
    if (!tieneFotoVehiculo) {
      _mostrarError('Agrega la foto de tu vehículo.');
      return;
    }
    if (placa.isEmpty) {
      _mostrarError('Ingresa el número de placa.');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _mostrarError('Sesión no válida. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotoPerfil != null
          ? await _subirImagen(_fotoPerfil!, 'foto', uid)
          : _fotoExistenteUrl!;
      final vehUrl = _fotoVehiculo != null
          ? await _subirImagen(_fotoVehiculo!, 'fotoVehiculo', uid)
          : _fotoVehiculoExistenteUrl!;

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'foto': fotoUrl,
        'fotoVehiculo': vehUrl,
        'placa': placa.toUpperCase(),
        'rol': 'conductor',
        'solicitudConductor': false,
        'servicioActivo': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const InicioConductor(mostrarBienvenida: true),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarError('No se pudo guardar el registro: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColores.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa el registro de conductor'),
        backgroundColor: AppColores.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () => _pickImage(esVehiculo: false),
                  child: CircleAvatar(
                    radius: 65,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _fotoPerfil != null
                        ? FileImage(File(_fotoPerfil!.path)) as ImageProvider
                        : (_fotoExistenteUrl != null &&
                                _fotoExistenteUrl!.isNotEmpty)
                            ? NetworkImage(_fotoExistenteUrl!)
                            : null,
                    child: (_fotoPerfil == null &&
                            (_fotoExistenteUrl == null ||
                                _fotoExistenteUrl!.isEmpty))
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.camera_alt,
                                size: 32,
                                color: Colors.black54,
                              ),
                              SizedBox(height: 6),
                              Text('Foto de perfil',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Foto del vehículo',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _pickImage(esVehiculo: true),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 170,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        child: _fotoVehiculo != null
                            ? Image.file(
                                File(_fotoVehiculo!.path),
                                fit: BoxFit.cover,
                              )
                            : (_fotoVehiculoExistenteUrl != null &&
                                    _fotoVehiculoExistenteUrl!.isNotEmpty)
                                ? Image.network(
                                    _fotoVehiculoExistenteUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.directions_car,
                                          size: 40, color: Colors.black54),
                                      SizedBox(height: 8),
                                      Text('Agregar foto del vehículo',
                                          style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () => _pickImage(esVehiculo: true),
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _placaController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Placa del vehículo',
                  prefixIcon: Icon(Icons.confirmation_number),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 28),
              CustomButton(
                text: _guardando ? 'Guardando...' : 'Guardar',
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
