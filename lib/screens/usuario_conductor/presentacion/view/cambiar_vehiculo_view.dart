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

/// Gestión de DOS vehículos (carro y moto).
/// Cada tipo tiene su propia foto y placa almacenadas en
/// `usuarios/{uid}.vehiculos.{tipo}`.
/// - "Guardar datos": guarda foto/placa del tipo seleccionado sin cambiar el activo.
/// - "Usar {tipo}": guarda + activa ese tipo (actualiza root fields).
class CambiarVehiculoView extends StatefulWidget {
  const CambiarVehiculoView({super.key});

  @override
  State<CambiarVehiculoView> createState() => _CambiarVehiculoViewState();
}

class _CambiarVehiculoViewState extends State<CambiarVehiculoView> {
  final ImagePicker _picker = ImagePicker();
  final ImageCropperService _cropper = const ImageCropperService();

  VehicleType _tipo = VehicleType.carro;
  VehicleType? _tipoActivo; // tipo activo guardado en Firestore

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
  bool _activando = false;

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
        final tipoStr = (data['tipoVehiculo'] ?? '').toString().toLowerCase();
        _tipoActivo = tipoStr == 'moto' ? VehicleType.moto : VehicleType.carro;
        _tipo = _tipoActivo!;

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

        // Migración legacy: campos raíz → sub-doc del tipo activo.
        final activeKey = _tipoActivo!.firestoreKey;
        if (mapa[activeKey] is! Map) {
          final t = _tipoActivo!;
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
      _mostrarError('Error seleccionando imagen: $e');
    }
  }

  Future<String> _subirImagen(XFile file, String uid) async {
    final path =
        'usuarios/$uid/fotoVehiculo_${_tipo.firestoreKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = fb_storage.FirebaseStorage.instance.ref().child(path);
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  bool _tieneDataCompleta(VehicleType t) =>
      (_fotosUrl[t]!.isNotEmpty || _fotosNuevas[t] != null) &&
      _placas[t]!.text.trim().isNotEmpty;

  bool get _puedeGuardar =>
      (_fotosNuevas[_tipo] != null || _fotosUrl[_tipo]!.isNotEmpty) &&
      _placas[_tipo]!.text.trim().isNotEmpty;

  /// Guarda foto + placa del tipo actual SIN cambiar el vehículo activo.
  Future<void> _guardarDatos() async {
    if (_guardando || _activando) return;
    if (!_validar()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _mostrarError('Sesión no válida.'); return; }

    setState(() => _guardando = true);
    try {
      final fotoUrl = _fotosNuevas[_tipo] != null
          ? await _subirImagen(_fotosNuevas[_tipo]!, uid)
          : _fotosUrl[_tipo]!;
      final placaUp = _placas[_tipo]!.text.trim().toUpperCase();

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set({
            'vehiculos': {
              _tipo.firestoreKey: {'foto': fotoUrl, 'placa': placaUp},
            },
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _fotosUrl[_tipo] = fotoUrl;
        _fotosNuevas[_tipo] = null;
        _placas[_tipo]!.text = placaUp;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Datos de ${_tipo.label} guardados.'),
          backgroundColor: AppColores.success,
        ),
      );
    } catch (e) {
      if (mounted) _mostrarError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Guarda foto + placa Y activa este vehículo como el activo.
  Future<void> _activarVehiculo() async {
    if (_guardando || _activando) return;
    if (!_validar()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { _mostrarError('Sesión no válida.'); return; }

    setState(() => _activando = true);
    try {
      final fotoUrl = _fotosNuevas[_tipo] != null
          ? await _subirImagen(_fotosNuevas[_tipo]!, uid)
          : _fotosUrl[_tipo]!;
      final placaUp = _placas[_tipo]!.text.trim().toUpperCase();

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .set({
            'vehiculos': {
              _tipo.firestoreKey: {'foto': fotoUrl, 'placa': placaUp},
            },
            'tipoVehiculo': _tipo.firestoreKey,
            'fotoVehiculo': fotoUrl,
            'placa': placaUp,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vehículo activo: ${_tipo.label}.'),
          backgroundColor: AppColores.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _activando = false);
        _mostrarError('No se pudo activar: $e');
      }
    }
  }

  bool _validar() {
    final tieneFoto =
        _fotosNuevas[_tipo] != null || _fotosUrl[_tipo]!.isNotEmpty;
    if (!tieneFoto) {
      _mostrarError('Agrega la foto de tu ${_tipo.label.toLowerCase()}.');
      return false;
    }
    if (_placas[_tipo]!.text.trim().isEmpty) {
      _mostrarError('Ingresa la placa de tu ${_tipo.label.toLowerCase()}.');
      return false;
    }
    return true;
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColores.error),
    );
  }

  Widget _tipoCard(VehicleType tipo, IconData icon) {
    final sel = _tipo == tipo;
    final activo = _tipoActivo == tipo;
    final tieneData = _tieneDataCompleta(tipo);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _tipo = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
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
            const SizedBox(height: 6),
            Text(
              tipo.label,
              style: TextStyle(
                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                fontSize: 15,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            if (activo)
              _Badge('Activo', AppColores.primary)
            else if (tieneData)
              _Badge('Registrado', AppColores.success)
            else
              _Badge('Sin datos', AppColores.grey400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fotoNueva = _fotosNuevas[_tipo];
    final fotoUrl = _fotosUrl[_tipo]!;
    final isBusy = _guardando || _activando;

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Mis vehículos'),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppColores.primary))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Selección de tipo ──────────────────────────────────
                    const Text(
                      'Selecciona el vehículo',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Puedes registrar carro y moto de forma independiente.',
                      style: TextStyle(fontSize: 12.5, color: AppColores.textSecondary),
                    ),
                    const SizedBox(height: 12),
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

                    const SizedBox(height: 28),

                    // ── Foto ──────────────────────────────────────────────
                    Text(
                      'Foto del ${_tipo.label.toLowerCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
                                  ? Image.file(File(fotoNueva.path), fit: BoxFit.cover)
                                  : fotoUrl.isNotEmpty
                                      ? Image.network(fotoUrl, fit: BoxFit.cover)
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
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
                                              style: const TextStyle(fontSize: 13),
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
                              child: const Icon(Icons.camera_alt, color: AppColores.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Placa ─────────────────────────────────────────────
                    TextField(
                      controller: _placas[_tipo],
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Placa del ${_tipo.label.toLowerCase()}',
                        prefixIcon: const Icon(Icons.confirmation_number),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 28),

                    // ── Botones ───────────────────────────────────────────
                    Row(
                      children: [
                        // Guardar datos sin activar
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isBusy || !_puedeGuardar
                                ? null
                                : _guardarDatos,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _puedeGuardar && !isBusy
                                    ? AppColores.primary
                                    : AppColores.grey300,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    'Guardar datos',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _puedeGuardar && !isBusy
                                          ? AppColores.primary
                                          : AppColores.grey400,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Activar vehículo
                        Expanded(
                          child: CustomButton(
                            text: _activando
                                ? 'Activando...'
                                : 'Usar ${_tipo.label}',
                            isLoading: _activando,
                            onPressed: isBusy || !_puedeGuardar
                                ? null
                                : _activarVehiculo,
                            height: 50,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Nota explicativa
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColores.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: AppColores.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '"Guardar datos" registra la foto y placa sin cambiar tu vehículo activo. '
                              '"Usar ${_tipo.label}" lo guarda y lo activa para recibir servicios.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColores.textSecondary,
                                height: 1.4,
                              ),
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
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
