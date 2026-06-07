import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/helpers/session_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/configuracion_aplicacion_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/completar_registro_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/membresia_detalle_view.dart';
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
    final user = _auth.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      if (mounted) setState(() => userData = <String, dynamic>{});
      return;
    }

    final Map<String, dynamic> data = {};

    // 1) Fuente principal: usuarios/{uid}
    try {
      final snap = await _firestore.collection('usuarios').doc(uid).get();
      final d = snap.data();
      if (snap.exists && d != null) data.addAll(d);
    } catch (_) {}

    // 2) Fallback a colecciones legacy si faltan datos clave (ej. conductores
    //    gestionados por admin guardan su perfil en `conductores`).
    final bool faltaNombre =
        (data['nombre'] ?? '').toString().trim().isEmpty;
    if (faltaNombre) {
      for (final col in const ['conductores', 'conductor', 'cliente']) {
        try {
          final s = await _firestore.collection(col).doc(uid).get();
          final d = s.data();
          if (s.exists && d != null) {
            // usuarios tiene prioridad: solo se rellenan campos ausentes.
            for (final e in d.entries) {
              data.putIfAbsent(e.key, () => e.value);
            }
            break;
          }
        } catch (_) {}
      }
    }

    // 3) Fallback final a la cuenta de Firebase Auth.
    data.putIfAbsent('nombre', () => user?.displayName ?? '');
    data.putIfAbsent('email', () => user?.email ?? '');
    if ((data['foto'] ?? '').toString().trim().isEmpty &&
        (data['fotoUrl'] ?? '').toString().trim().isEmpty) {
      final photo = user?.photoURL;
      if (photo != null && photo.isNotEmpty) data['foto'] = photo;
    }

    if (!mounted) return;
    setState(() => userData = data);

    // Preparar caché de imagen: usar imagen local si existe, sino descargarla.
    try {
      final fotoUrl = (data['foto'] ?? data['fotoUrl'])?.toString();
      await _loadCachedImageForUid(uid, fotoUrl);
      final vehUrl = data['fotoVehiculo']?.toString();
      await _loadCachedVehicleImageForUid(uid, vehUrl);
    } catch (_) {}
  }

  Future<void> _guardarCambios(Map<String, dynamic> nuevosDatos) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _guardando = false);
      return;
    }
    await _firestore
        .collection('usuarios')
        .doc(uid)
        .set(nuevosDatos, SetOptions(merge: true));
    // Guardar nombre en caché si se actualizó
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
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_comp.webp';

      // get original dimensions
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ui.Image original = frame.image;
      final int origW = original.width;
      final int origH = original.height;

      final qualities = [80, 70, 60, 50, 45, 40, 35, 30, 25];
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
            format: CompressFormat.webp,
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

  // ignore: unused_element
  Future<void> _uploadFile(File file) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // obtener url anterior para borrarla luego
    String? previousUrl;
    try {
      final doc = await _firestore.collection('usuarios').doc(uid).get();
      previousUrl = doc.data()?['foto'] as String?;
    } catch (_) {}

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final compressed = await _compressFile(file, maxBytes: 100 * 1024);
      final path =
          'usuarios/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.webp';
      final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);

      final uploadTask = ref.putFile(compressed);

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

      await _firestore.collection('usuarios').doc(uid).set({
        'foto': downloadUrl,
      }, SetOptions(merge: true));

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

      // Actualizar caché local con la nueva imagen
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
  // ignore: unused_element
  Future<void> _uploadFileForField(File file, String fieldName) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // obtener url anterior para borrarla luego
    String? previousUrl;
    try {
      final doc = await _firestore.collection('usuarios').doc(uid).get();
      previousUrl = doc.data()?[fieldName] as String?;
    } catch (_) {}

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final compressed = await _compressFile(file, maxBytes: 100 * 1024);
      final path =
          'usuarios/$uid/${fieldName}_${DateTime.now().millisecondsSinceEpoch}.webp';
      final ref = firebase_storage.FirebaseStorage.instance.ref().child(path);

      final uploadTask = ref.putFile(compressed);

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

      await _firestore.collection('usuarios').doc(uid).set({
        fieldName: downloadUrl,
      }, SetOptions(merge: true));

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

      // Borrar/actualizar caché local para foto del vehículo si corresponde
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
    final nombreController = TextEditingController(
      text: userData?['nombre'] ?? '',
    );
    final telefonoController = TextEditingController(
      text: userData?['telefono'] ?? '',
    );
    final placaController = TextEditingController(
      text: userData?['placa'] ?? '',
    );
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
              // Eliminar imagen de perfil anterior del caché local si hay nueva URL
              final fotoUrl = datos['foto'] as String?;
              if (fotoUrl != null && fotoUrl.isNotEmpty) {
                final cacheFile = await _cacheFileForUid(uid);
                if (cacheFile.existsSync()) {
                  if (mounted) {
                    setState(() => _cachedImageFile = null);
                  }
                  try {
                    await FileImage(cacheFile).evict();
                  } catch (_) {}
                  await cacheFile.delete();
                }
                await _downloadAndSaveImage(fotoUrl, uid);
              }
              // Eliminar imagen del vehículo anterior del caché local si hay nueva URL
              final vehUrl = datos['fotoVehiculo'] as String?;
              if (vehUrl != null && vehUrl.isNotEmpty) {
                final cacheFile = await _vehicleCacheFileForUid(uid);
                if (cacheFile.existsSync()) {
                  if (mounted) {
                    setState(() => _cachedVehicleFile = null);
                  }
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

  Widget _buildSerConductorCard() {
    // Si ya tiene datos de conductor guardados (placa + foto vehículo), solo
    // cambia de vista a InicioConductor sin volver a registrar.
    final placa = (userData?['placa'] ?? '').toString().trim();
    final fotoVeh = (userData?['fotoVehiculo'] ?? '').toString().trim();
    final yaRegistrado = placa.isNotEmpty && fotoVeh.isNotEmpty;

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: ListTile(
        leading: Icon(Icons.local_taxi, color: AppColores.primary),
        title: Text(
          yaRegistrado ? 'Modo conductor' : 'Ser conductor',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          yaRegistrado
              ? 'Entra como conductor'
              : 'Completa tu registro y empieza a recibir viajes',
        ),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 0.5),
        ),
        onTap: () {
          if (yaRegistrado) {
            // Cambiar rol a conductor (Firestore + caché) para que al
            // reiniciar la app abra como conductor.
            final uid = _auth.currentUser?.uid;
            if (uid != null) {
              _firestore.collection('usuarios').doc(uid).set({
                'rol': 'conductor',
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
            SessionHelper.updateRole('conductor');
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const InicioConductor()),
              (route) => false,
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CompletarRegistroConductorView(),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildVolverClienteCard() {
    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: ListTile(
        leading: Icon(Icons.person_outline, color: AppColores.primary),
        title: const Text(
          'Volver a ser cliente',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('Usa la app como cliente'),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.wp(context, 4),
          vertical: ResponsiveHelper.hp(context, 0.5),
        ),
        onTap: () {
          final uid = _auth.currentUser?.uid;
          if (uid != null) {
            // Fire-and-forget: no bloquear la navegación esperando la red.
            // rol cliente + quitar solicitud → retira notif del admin.
            _firestore.collection('usuarios').doc(uid).set({
              'rol': 'cliente',
              'solicitudConductor': false,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            // Sincronizar caché para que al reiniciar abra como cliente.
            SessionHelper.updateRole('cliente');
          }
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeClienteView()),
            (route) => false,
          );
        },
      ),
    );
  }

  Widget _buildMembresiaConductorCard() {
    final activa =
        (userData?['membresia'] ?? '').toString().toLowerCase() == 'activa';
    final dias = userData?['membresiaDias'];
    final venceTs = userData?['membresiaVence'];
    String? venceStr;
    int? diasRestantes;
    if (venceTs is Timestamp) {
      final d = venceTs.toDate();
      venceStr =
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      diasRestantes = d.difference(DateTime.now()).inDays;
      if (diasRestantes < 0) diasRestantes = 0;
    }
    final color = activa ? AppColores.success : AppColores.error;

    return Card(
      margin: EdgeInsets.symmetric(vertical: ResponsiveHelper.hp(context, 0.8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  MembresiaDetalleView(data: userData ?? const {}),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 4),
            vertical: ResponsiveHelper.hp(context, 1.5),
          ),
          child: Row(
            children: [
              Icon(activa ? Icons.verified : Icons.cancel,
                  color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activa ? 'Estás activo' : 'No estás activo',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activa
                          ? (dias != null
                                ? 'Membresía activa · $dias días'
                                      '${diasRestantes != null ? ' · faltan $diasRestantes días' : ''}'
                                      '${venceStr != null ? ' · vence $venceStr' : ''}'
                                : 'Membresía activa')
                          : 'Activa tu membresía para recibir viajes',
                      style: const TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Toca para más detalles',
                      style: TextStyle(
                        color: AppColores.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColores.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreCompleto = [
      (userData?['nombre'] ?? '').toString().trim(),
      (userData?['apellido'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).join(' ').trim();
    final nombre = nombreCompleto.isEmpty ? 'Usuario' : nombreCompleto;
    final correo =
        (userData?['correo'] ?? userData?['email'] ?? 'Sin correo registrado')
            .toString();
    final telefono = (userData?['telefono'] ?? 'Sin teléfono registrado')
        .toString();
    final fotoUrl = (userData?['foto'] ?? userData?['fotoUrl'] ?? '')
        .toString();

    // Responsive sizes based on screen dimensions and safe clamps
    final screenWidth = MediaQuery.of(context).size.width;

    final double appBarFontSize = (screenWidth * 0.05).clamp(18.0, 22.0);
    double computedNameFontSize = (screenWidth * 0.06).clamp(18.0, 26.0);
    double avatarRadius = (screenWidth * 0.14).clamp(36.0, 70.0);
    final double avatarIconSize = (avatarRadius * 0.9).clamp(28.0, 56.0);

    // Adjust name font size for very long names
    if (nombre.length > 18 && nombre.length <= 26) {
      computedNameFontSize = math.max(18.0, computedNameFontSize * 0.9);
    } else if (nombre.length > 26) {
      computedNameFontSize = math.max(16.0, computedNameFontSize * 0.8);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.tipoUsuario == 'cliente'
            ? false
            : true,
        title: Text('Perfil', style: TextStyle(fontSize: appBarFontSize)),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConfiguracionAplicacionView(),
                ),
              );
            },
          ),
        ],
      ),
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: ResponsiveHelper.wp(context, 4),
                      right: ResponsiveHelper.wp(context, 4),
                      top: ResponsiveHelper.hp(context, 0.5),
                      bottom: ResponsiveHelper.hp(context, 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                    : (fotoUrl.isNotEmpty
                                          ? NetworkImage(fotoUrl)
                                          : null),
                                child:
                                    (_cachedImageFile == null ||
                                            !(_cachedImageFile?.existsSync() ??
                                                false)) &&
                                        fotoUrl.isEmpty
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
                        SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                        if (widget.tipoUsuario == 'conductor') ...[
                          // Orden: estado/días → vehículo → correo → teléfono
                          // → volver a ser cliente.
                          _buildMembresiaConductorCard(),
                          SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                          _buildVehiclePhotoCard(),
                          SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                          if (correo.isNotEmpty &&
                              correo != 'Sin correo registrado') ...[
                            _buildInfoCard(Icons.email, 'Correo', correo),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                          ],
                          _buildInfoCard(Icons.phone, 'Teléfono', telefono),
                          SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                          _buildVolverClienteCard(),
                        ] else ...[
                          if (correo.isNotEmpty &&
                              correo != 'Sin correo registrado') ...[
                            _buildInfoCard(Icons.email, 'Correo', correo),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                          ],
                          _buildInfoCard(Icons.phone, 'Teléfono', telefono),
                          if (widget.tipoUsuario == 'cliente' ||
                              (userData?['rol'] ?? '')
                                      .toString()
                                      .toLowerCase() ==
                                  'cliente') ...[
                            SizedBox(height: ResponsiveHelper.hp(context, 0.4)),
                            _buildSerConductorCard(),
                          ],
                        ],
                        SizedBox(height: ResponsiveHelper.hp(context, 1.4)),
                        // NOTE: Buttons moved to bottom fixed area
                        // SizedBox(height: ResponsiveHelper.hp(context, 1)),
                        // OutlinedButton.icon(
                        //   onPressed: () {
                        //     Navigator.of(context).push(
                        //       MaterialPageRoute(
                        //         builder: (_) => const CambiarContrasenaScreen(),
                        //       ),
                        //     );
                        //   },
                        //   icon: const Icon(
                        //     Icons.lock_outline,
                        //     size: buttonIconSize,
                        //   ),
                        //   label: const Text(
                        //     'Cambiar contraseña',
                        //     style: TextStyle(fontSize: buttonFontSize),
                        //   ),
                        //   style: OutlinedButton.styleFrom(
                        //     foregroundColor: AppColores.textPrimary,
                        //     side: const BorderSide(color: AppColores.borderSubtle),
                        //     padding: EdgeInsets.symmetric(
                        //       vertical: ResponsiveHelper.hp(context, 1.5),
                        //       horizontal: ResponsiveHelper.wp(context, 2),
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                  ),

                  // Barra inferior fija con el botón
                  Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.wp(context, 4),
                        vertical: ResponsiveHelper.hp(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: AppColores.background,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: ElevatedButton.icon(
                              onPressed: _mostrarDialogoEditar,
                              icon: const Icon(Icons.edit, size: 20),
                              label: const Text('Editar Datos'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textWhite,
                                minimumSize: const Size.fromHeight(48),
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.hp(context, 1.2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
