import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:ui' as ui;
import 'package:taxi_app/core/app_colores.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/helper/session_helper.dart';
import 'package:taxi_app/screens/cambiar_contrasena_screen.dart';
import 'package:taxi_app/screens/eliminar_cuenta_screen.dart';
import 'package:taxi_app/screens/home_screen.dart';
import 'package:taxi_app/models/AuthModel.dart';
import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:taxi_app/data/models/viewmodels/perfil_viewmodel.dart';
import 'package:taxi_app/widgets/editar_perfil.dart';

class PaginaPerfilUsuario extends StatefulWidget {
  final String tipoUsuario; // 'cliente' o 'conductor'

  const PaginaPerfilUsuario({super.key, required this.tipoUsuario});

  @override
  State<PaginaPerfilUsuario> createState() => _PaginaPerfilUsuarioState();
}

class _PaginaPerfilUsuarioState extends State<PaginaPerfilUsuario> {
    bool _guardando = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Map<String, dynamic>? userData;
  File? _cachedImageFile;
  File? _cachedVehicleFile;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await _firestore
        .collection(widget.tipoUsuario)
        .doc(uid)
        .get();

    if (snapshot.exists) {
      if (!mounted) return;
      setState(() {
        userData = snapshot.data();
      });
      // Preparar cache de imagen: usar imagen local si existe, sino descargarla
      try {
        final fotoUrl = userData?['foto']?.toString();
        await _loadCachedImageForUid(uid, fotoUrl);
        // cargar cache de foto del vehículo (si aplica)
        final vehUrl = userData?['fotoVehiculo']?.toString();
        await _loadCachedVehicleImageForUid(uid, vehUrl);
      } catch (_) {}
    }
  }

  Future<void> _guardarCambios(Map<String, dynamic> nuevosDatos) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _guardando = false);
      return;
    }
    await _firestore.collection(widget.tipoUsuario).doc(uid).update(nuevosDatos);
    // Guardar nombre en cache si se actualizó
    try {
      final n = nuevosDatos['nombre']?.toString();
      if (n != null && n.trim().isNotEmpty) {
        await SessionHelper.saveCachedName(n.trim());
      }
    } catch (_) {}
    _cargarDatos();
    // Mensaje de 'Datos guardados' eliminado por solicitud
    setState(() => _guardando = false);
  }

  Future<File> _compressFile(File file, {required int maxBytes}) async {
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.jpg';

      // get original dimensions
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image original = frame.image;
      final int origW = original.width;
      final int origH = original.height;

      final qualities = [95, 85, 75, 65, 55, 45, 35, 30];
      final scales = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4];

      File? best;
      for (final s in scales) {
        final targetW = (origW * s).toInt();
        final targetH = (origH * s).toInt();
        for (final q in qualities) {
          final result = await FlutterImageCompress.compressAndGetFile(
            file.absolute.path,
            outPath,
            quality: q,
            minWidth: targetW,
            minHeight: targetH,
          );
          if (result == null) continue;
          final len = await result.length();
          final wrapped = File(result.path);
          best = wrapped;
          if (len <= maxBytes) return wrapped;
        }
      }
      return best ?? file;
    } catch (_) {
      return file;
    }
  }

  Future<File> _cacheFileForUid(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/profile_$uid.jpg';
    return File(path);
  }

  Future<void> _loadCachedImageForUid(String uid, String? fotoUrl) async {
    try {
      final file = await _cacheFileForUid(uid);
      if (file.existsSync()) {
        if (mounted) {
          setState(() {
            _cachedImageFile = file;
          });
        }
        return;
      }
      if (fotoUrl == null || fotoUrl.isEmpty) return;
      await _downloadAndSaveImage(fotoUrl, uid);
    } catch (_) {}
  }

  Future<void> _downloadAndSaveImage(String url, String uid) async {
    try {
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return;
      final file = await _cacheFileForUid(uid);
      final iosink = file.openWrite();
      await response.pipe(iosink);
      await iosink.flush();
      await iosink.close();
      // Evict any existing cached image for this file path so Flutter reloads it
      try {
        await FileImage(file).evict();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _cachedImageFile = file;
        });
      }
    } catch (_) {}
  }

  Future<File> _vehicleCacheFileForUid(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/vehicle_$uid.jpg';
    return File(path);
  }

  Future<void> _loadCachedVehicleImageForUid(
    String uid,
    String? fotoVehiculoUrl,
  ) async {
    try {
      final file = await _vehicleCacheFileForUid(uid);
      if (file.existsSync()) {
        if (mounted) {
          setState(() {
            _cachedVehicleFile = file;
          });
        }
        return;
      }
      if (fotoVehiculoUrl == null || fotoVehiculoUrl.isEmpty) return;
      await _downloadAndSaveVehicleImage(fotoVehiculoUrl, uid);
    } catch (_) {}
  }

  Future<void> _downloadAndSaveVehicleImage(String url, String uid) async {
    try {
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return;
      final file = await _vehicleCacheFileForUid(uid);
      final iosink = file.openWrite();
      await response.pipe(iosink);
      await iosink.flush();
      await iosink.close();
      try {
        await FileImage(file).evict();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _cachedVehicleFile = file;
        });
      }
    } catch (_) {}
  }

  Future<void> _deleteCachedVehicleFile(String uid) async {
    try {
      final file = await _vehicleCacheFileForUid(uid);
      if (file.existsSync()) {
        try {
          await FileImage(file).evict();
        } catch (_) {}
        await file.delete();
      }
      if (mounted) setState(() => _cachedVehicleFile = null);
    } catch (_) {}
  }

  Future<void> _uploadFile(File file) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // obtener url anterior para borrarla luego
    String? previousUrl;
    try {
      final doc = await _firestore
          .collection(widget.tipoUsuario)
          .doc(uid)
          .get();
      previousUrl = doc.data()?['foto'] as String?;
    } catch (_) {}

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final path =
          '${widget.tipoUsuario}/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);

      final uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        }
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await _firestore.collection(widget.tipoUsuario).doc(uid).update({
        'foto': downloadUrl,
      });

      // Intentar eliminar la foto anterior en Storage para no acumular archivos
      if (previousUrl != null &&
          previousUrl.isNotEmpty &&
          previousUrl != downloadUrl) {
        try {
          final oldRef = firebase_storage.FirebaseStorage.instance.refFromURL(
            previousUrl,
          );
          await oldRef.delete();
        } catch (_) {}
      }

      // Actualizar cache local con la nueva imagen
      try {
        await _downloadAndSaveImage(downloadUrl, uid);
      } catch (_) {}
      await _cargarDatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle),
                SizedBox(width: 8),
                Expanded(child: Text('Foto de perfil actualizada')),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error subiendo imagen: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  // Variante que sube un archivo y actualiza un campo arbitrario en Firestore
  Future<void> _uploadFileForField(File file, String fieldName) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // obtener url anterior para borrarla luego
    String? previousUrl;
    try {
      final doc = await _firestore
          .collection(widget.tipoUsuario)
          .doc(uid)
          .get();
      previousUrl = doc.data()?[fieldName] as String?;
    } catch (_) {}

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final path =
          '${widget.tipoUsuario}/$uid/${fieldName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);

      final uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        }
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await _firestore.collection(widget.tipoUsuario).doc(uid).update({
        fieldName: downloadUrl,
      });

      // Intentar eliminar la foto anterior en Storage
      if (previousUrl != null &&
          previousUrl.isNotEmpty &&
          previousUrl != downloadUrl) {
        try {
          final oldRef = firebase_storage.FirebaseStorage.instance.refFromURL(
            previousUrl,
          );
          await oldRef.delete();
        } catch (_) {}
      }

      // Borrar/actualizar cache local para foto del vehículo si corresponde
      if (fieldName == 'fotoVehiculo') {
        try {
          await _deleteCachedVehicleFile(uid);
        } catch (_) {}
        try {
          await _downloadAndSaveVehicleImage(downloadUrl, uid);
        } catch (_) {}
      }

      await _cargarDatos();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle),
                SizedBox(width: 8),
                Expanded(child: Text('Imagen subida')),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error subiendo imagen: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  void _mostrarDialogoEditar() {
    final nombreController = TextEditingController(text: userData?['nombre'] ?? '');
    final telefonoController = TextEditingController(text: userData?['telefono'] ?? '');
    final placaController = TextEditingController(text: userData?['placa'] ?? '');
    final esConductor = widget.tipoUsuario == 'conductor';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditarPerfilScreen(
          nombreController: nombreController,
          telefonoController: telefonoController,
          placaController: placaController,
          esConductor: esConductor,
          selectedImage: _cachedImageFile,
          selectedVehicleImage: _cachedVehicleFile,
          onImageChanged: (file) async {
            final uid = _auth.currentUser?.uid;
            if (uid != null && file != null) {
              final cacheFile = await _cacheFileForUid(uid);
              await file.copy(cacheFile.path);
              setState(() {
                _cachedImageFile = cacheFile;
              });
            }
          },
          onVehicleImageChanged: (file) async {
            final uid = _auth.currentUser?.uid;
            if (uid != null && file != null) {
              final cacheFile = await _vehicleCacheFileForUid(uid);
              await file.copy(cacheFile.path);
              setState(() {
                _cachedVehicleFile = cacheFile;
              });
            }
          },
          onSave: (datos) async {
            await _guardarCambios(datos);
            final uid = _auth.currentUser?.uid;
            if (uid != null) {
              // Eliminar imagen de perfil anterior del cache local si hay nueva URL
              final fotoUrl = datos['foto'] as String?;
              if (fotoUrl != null && fotoUrl.isNotEmpty) {
                final cacheFile = await _cacheFileForUid(uid);
                if (cacheFile.existsSync()) {
                  try {
                    await FileImage(cacheFile).evict();
                  } catch (_) {}
                  await cacheFile.delete();
                }
                await _downloadAndSaveImage(fotoUrl, uid);
              }
              // Eliminar imagen del vehículo anterior del cache local si hay nueva URL
              final vehUrl = datos['fotoVehiculo'] as String?;
              if (vehUrl != null && vehUrl.isNotEmpty) {
                final cacheFile = await _vehicleCacheFileForUid(uid);
                if (cacheFile.existsSync()) {
                  try {
                    await FileImage(cacheFile).evict();
                  } catch (_) {}
                  await cacheFile.delete();
                }
                await _downloadAndSaveVehicleImage(vehUrl, uid);
              }
            }
          },
        ),
      ),
    );
  }


  Widget _buildInfoCard(IconData icon, String title, String value) {
    const double iconSize = 24.0;
    const double titleFontSize = 16.0;
    const double valueFontSize = 14.0;

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColores.primary, size: iconSize),
            SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: titleFontSize,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: valueFontSize),
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildVehiclePhotoCard() {
    ImageProvider? imageProvider;
    if (_cachedVehicleFile != null &&
        (_cachedVehicleFile?.existsSync() ?? false)) {
      imageProvider = FileImage(_cachedVehicleFile!);
    } else if (userData != null &&
        userData!['fotoVehiculo'] != null &&
        (userData!['fotoVehiculo'] as String).isNotEmpty) {
      imageProvider = NetworkImage(userData!['fotoVehiculo'] as String);
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: ListTile(
        leading: Icon(Icons.directions_car, color: AppColores.primary),
        title: const Text(
          'Foto del vehículo',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 80,
            height: 48,
            color: Colors.grey.shade200,
            child: imageProvider != null
                ? Image(image: imageProvider, fit: BoxFit.cover)
                : const Icon(Icons.directions_car, color: Colors.white),
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (userData?['nombre'] ?? 'Usuario').toString();

    // Instanciar el viewmodel para censurar correo y teléfono
    final perfilViewModel = PerfilViewModel(
      correo: userData?['correo']?.toString(),
      telefono: userData?['telefono']?.toString(),
    );

    // Tamaños base estándar
    const double appBarFontSize = 20.0;
    const double baseNameFontSize = 22.0;
    const double avatarRadius = 50.0;
    const double avatarIconSize = 45.0;
    const double buttonFontSize = 16.0;
    const double buttonIconSize = 24.0;

    // Ajuste simple de tamaño para nombres muy largos
    double computedNameFontSize = baseNameFontSize;
    if (nombre.length > 18 && nombre.length <= 26) {
      computedNameFontSize = 20.0;
    } else if (nombre.length > 26) {
      computedNameFontSize = 18.0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil', style: TextStyle(fontSize: appBarFontSize)),
      ),
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(ResponsiveHelper.wp(context, 4)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Reduce vertical space above profile photo
                      SizedBox(height: ResponsiveHelper.hp(context, 0.5)),
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: avatarRadius,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage:
                                  _cachedImageFile != null &&
                                      _cachedImageFile!.existsSync()
                                  ? FileImage(_cachedImageFile!)
                                        as ImageProvider
                                  : (userData != null &&
                                        userData!['foto'] != null &&
                                        (userData!['foto'] as String)
                                            .isNotEmpty)
                                  ? NetworkImage(userData!['foto'] as String)
                                  : null,
                              child:
                                  (_cachedImageFile == null ||
                                          !(_cachedImageFile?.existsSync() ??
                                              false)) &&
                                      (userData == null ||
                                          userData!['foto'] == null ||
                                          (userData!['foto'] as String).isEmpty)
                                  ? Icon(
                                      Icons.person,
                                      size: avatarIconSize,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            if (_isUploading)
                              Positioned(
                                bottom: -6,
                                child: SizedBox(
                                  width: avatarRadius * 1.8,
                                  child: LinearProgressIndicator(
                                    value: _uploadProgress,
                                  ),
                                ),
                              ),
                            // Edit overlay removed from main avatar: editing available only inside the edit dialog
                          ],
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.hp(context, 2)),
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: ResponsiveHelper.wp(context, 80),
                          ),
                          child: Text(
                            nombre.toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: computedNameFontSize,
                              fontWeight: FontWeight.bold,
                              color: AppColores.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.hp(context, 1)),
                      // Conductor connection toggle moved to driver home view
                      SizedBox(height: ResponsiveHelper.hp(context, 1)),
                      // Cards para ambos tipos de usuario
                      if (widget.tipoUsuario == 'conductor') ...[
                        _buildVehiclePhotoCard(),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        _buildInfoCard(
                          Icons.local_taxi,
                          'Placa',
                          userData?['placa'] ?? 'Sin placa registrada',
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        _buildInfoCard(
                          Icons.email,
                          'Correo',
                          perfilViewModel.correoCensurado,
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        _buildInfoCard(
                          Icons.phone,
                          'Teléfono',
                          perfilViewModel.telefonoCensurado,
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        // Cards de acción juntos y con mismo espacio
                        Column(
                          children: [
                            Card(
                              margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.4)),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const CambiarContrasenaScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 56),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.wp(context, 4),
                                    vertical: ResponsiveHelper.hp(context, 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.lock, color: AppColores.primary, size: 24.0),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Cambiar contraseña',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16.0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.8)),
                            Card(
                              margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.4)),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const EliminarCuentaScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 56),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.wp(context, 4),
                                    vertical: ResponsiveHelper.hp(context, 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red, size: 24.0),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Eliminar cuenta',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16.0,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                          ],
                        ),
                      ]
                      else ...[
                        _buildInfoCard(
                          Icons.email,
                          'Correo',
                          perfilViewModel.correoCensurado,
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        _buildInfoCard(
                          Icons.phone,
                          'Teléfono',
                          perfilViewModel.telefonoCensurado,
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                        // Cards de acción juntos y con mismo espacio
                        Column(
                          children: [
                            Card(
                              margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.4)),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const CambiarContrasenaScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 56),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.wp(context, 4),
                                    vertical: ResponsiveHelper.hp(context, 1.5),
                                  ),
                                  child: Row(
                                    
                                    children: [
                                      Icon(Icons.lock, color: AppColores.primary, size: 24.0),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Cambiar contraseña',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16.0,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.8)),
                            Card(
                              margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.4)),
                              child: InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const EliminarCuentaScreen(),
                                    ),
                                  );
                                },
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 56),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.wp(context, 4),
                                    vertical: ResponsiveHelper.hp(context, 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red, size: 24.0),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Eliminar cuenta',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16.0,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                          ],
                        ),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _mostrarDialogoEditar,
                              icon: const Icon(
                                Icons.edit,
                                size: buttonIconSize,
                              ),
                              label: const Text(
                                "Editar Datos",
                                style: TextStyle(fontSize: buttonFontSize),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textWhite,
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.hp(context, 1.5),
                                  horizontal: ResponsiveHelper.wp(context, 2),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.wp(context, 3)),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                // Tamaños fijos para el diálogo de confirmación
                                const double dialogIconSize = 38.0;
                                const double dialogTextSize = 18.0;
                                const double dialogButtonSize = 14.0;

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) {
                                    // Diálogo responsive sin altura fija
                                    final dialogWidth = ResponsiveHelper.wp(
                                      context,
                                      75,
                                    );

                                    return Dialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          12.0,
                                        ),
                                      ),
                                      child: Container(
                                        width: dialogWidth,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveHelper.wp(
                                            context,
                                            4,
                                          ),
                                          vertical: ResponsiveHelper.hp(
                                            context,
                                            2.5,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Ícono
                                            const Icon(
                                              Icons.logout,
                                              color: Colors.redAccent,
                                              size: dialogIconSize,
                                            ),

                                            SizedBox(
                                              height: ResponsiveHelper.hp(
                                                context,
                                                2,
                                              ),
                                            ),

                                            // Texto
                                            Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: ResponsiveHelper.wp(
                                                  context,
                                                  2,
                                                ),
                                              ),
                                              child: const Text(
                                                '¿Deseas cerrar sesión?',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: dialogTextSize,
                                                  height: 1.3,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),

                                            SizedBox(
                                              height: ResponsiveHelper.hp(
                                                context,
                                                3,
                                              ),
                                            ),

                                            // Botones
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(false),
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(
                                                        color: Colors.redAccent,
                                                      ),
                                                      padding: EdgeInsets.symmetric(
                                                        vertical:
                                                            ResponsiveHelper.hp(
                                                              context,
                                                              1.5,
                                                            ),
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'Cancelar',
                                                      style: TextStyle(
                                                        fontSize:
                                                            dialogButtonSize,
                                                        color: AppColores
                                                            .buttonCancel,
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                SizedBox(
                                                  width: ResponsiveHelper.wp(
                                                    context,
                                                    3,
                                                  ),
                                                ),

                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          context,
                                                        ).pop(true),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.redAccent,
                                                      foregroundColor:
                                                          AppColores.textWhite,
                                                      padding: EdgeInsets.symmetric(
                                                        vertical:
                                                            ResponsiveHelper.hp(
                                                              context,
                                                              1.5,
                                                            ),
                                                      ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'Cerrar sesión',
                                                      style: TextStyle(
                                                        fontSize:
                                                            dialogButtonSize,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );

                                if (confirm == true) {
                                  // Capture the BuildContext and NavigatorState before async gaps.
                                  final BuildContext ctx = context;
                                  final navigator = Navigator.of(ctx);

                                  // Mostrar diálogo de progreso mientras se cierra la sesión
                                  showDialog<void>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (ctx) {
                                      return AlertDialog(
                                        content: SizedBox(
                                          height: 60,
                                          child: Row(
                                            children: const [
                                              CircularProgressIndicator(),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Text(
                                                  'Cerrando sesión...',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                  try {
                                    // Usar el ViewModel / repositorio para cerrar sesión
                                    final vm = Provider.of<AuthViewModel>(
                                      context,
                                      listen: false,
                                    );
                                    final uidBeforeLogout =
                                        _auth.currentUser?.uid;

                                    // Este logout ya limpia SessionHelper, rutas activas
                                    // y caches de ruta en FirebaseDataSource.logout
                                    await vm.logout();

                                    // Refuerzo: limpiar cualquier dato de sesión
                                    // residual y solicitud activa.
                                    try {
                                      await SessionHelper.clearSession();
                                    } catch (_) {}
                                    try {
                                      await SessionHelper.clearActiveSolicitud();
                                    } catch (_) {}

                                    // Borrar cache local de fotos (perfil y vehículo)
                                    try {
                                      if (uidBeforeLogout != null) {
                                        // Foto de perfil en disco
                                        final f = await _cacheFileForUid(
                                          uidBeforeLogout,
                                        );
                                        if (f.existsSync()) {
                                          await f.delete();
                                        }

                                        // Foto de vehículo en disco (si existe)
                                        await _deleteCachedVehicleFile(
                                          uidBeforeLogout,
                                        );

                                        if (mounted) {
                                          setState(() {
                                            _cachedImageFile = null;
                                            _cachedVehicleFile = null;
                                          });
                                        }
                                      }
                                    } catch (_) {}
                                  } finally {
                                    // Mantener el diálogo de progreso visible un poco más
                                    await Future.delayed(
                                      const Duration(milliseconds: 1500),
                                    );

                                    // Use the captured BuildContext's mounted flag before using it.
                                    if (ctx.mounted) {
                                      if (navigator.mounted) {
                                        try {
                                          navigator.pop();
                                        } catch (_) {}
                                        try {
                                          navigator.pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) => const HomeView(),
                                            ),
                                          );
                                        } catch (_) {}
                                      } else {
                                        try {
                                          Navigator.pushReplacement(
                                            ctx,
                                            MaterialPageRoute(
                                              builder: (_) => const HomeView(),
                                            ),
                                          );
                                        } catch (_) {}
                                      }
                                    }
                                  }
                                }
                              },
                              icon: const Icon(
                                Icons.logout,
                                size: buttonIconSize,
                              ),
                              label: const Text(
                                'Cerrar Sesión',
                                style: TextStyle(fontSize: buttonFontSize),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.hp(context, 1.5),
                                  horizontal: ResponsiveHelper.wp(context, 2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
