import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/core/services/image_upload_service.dart';
import 'package:taxi_app/core/services/optimizador_imagen.dart';

import '../../dominio/entidades/anuncio.dart';
import '../../dominio/entidades/promocion.dart';
import '../../dominio/repositorios/anuncios_repository.dart';

/// `anuncios` y `promociones` en Firestore. Las imágenes se suben a la
/// carpeta del propio admin (`usuarios/{uid}/...`): `storage.rules` ya deja
/// que el dueño escriba ahí y que cualquiera con sesión las lea, sin abrir
/// rutas nuevas.
class AnunciosRepositoryImpl implements AnunciosRepository {
  AnunciosRepositoryImpl({
    FirebaseFirestore? firestore,
    ImageUploadService? imagenes,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _imagenesOverride = imagenes;

  final FirebaseFirestore _firestore;
  final ImageUploadService? _imagenesOverride;

  // Perezoso: el carrusel y el modal solo leen Firestore; Storage se toca
  // recién al subir o borrar una imagen.
  late final ImageUploadService _imagenes =
      _imagenesOverride ?? ImageUploadService();

  @override
  Stream<List<Anuncio>> watchAnuncios() => _firestore
      .collection('anuncios')
      .orderBy('creadoEn', descending: true)
      .limit(30)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) {
              final data = d.data();
              final url = '${data['imagenUrl'] ?? ''}';
              if (url.isEmpty) return null;
              return Anuncio(
                id: d.id,
                imagenUrl: url,
                // Recién creado y aún sin hora del servidor: ahora.
                creadoEn:
                    (data['creadoEn'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
                venceEn: (data['venceEn'] as Timestamp?)?.toDate(),
                titulo: '${data['titulo'] ?? ''}',
                detalle: '${data['detalle'] ?? ''}',
                whatsapp: '${data['whatsapp'] ?? ''}',
                instagram: '${data['instagram'] ?? ''}',
              );
            })
            .whereType<Anuncio>()
            .toList(),
      );

  /// Topes de la imagen subida: nítida a su ancho completo y liviana para
  /// Storage y para quien la descarga en datos móviles.
  static const _anchosAnuncio = [1500, 1350, 1200, 1080];
  static const _maxBytesAnuncio = 350 * 1024;
  static const _anchosPromocion = [1080, 960, 860];
  static const _maxBytesPromocion = 250 * 1024;

  Future<String> _subir(
    Uint8List imagen,
    String prefijo, {
    required double proporcion,
    required List<int> anchos,
    required int maxBytes,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final webp = await optimizarAWebP(
      imagen,
      proporcion: proporcion,
      anchos: anchos,
      maxBytes: maxBytes,
    );
    return _imagenes.uploadBytes(
      bytes: webp,
      storagePath:
          'usuarios/$uid/${prefijo}_${DateTime.now().millisecondsSinceEpoch}.webp',
    );
  }

  Future<String> _subirAnuncio(Uint8List imagen) => _subir(
    imagen,
    'anuncio',
    proporcion: kProporcionAnuncio,
    anchos: _anchosAnuncio,
    maxBytes: _maxBytesAnuncio,
  );

  Future<String> _subirPromocion(Uint8List imagen) => _subir(
    imagen,
    'promocion',
    proporcion: 1,
    anchos: _anchosPromocion,
    maxBytes: _maxBytesPromocion,
  );

  static Timestamp? _vence(int dias) =>
      Timestamp.fromDate(DateTime.now().add(Duration(days: dias)));

  @override
  Future<void> crearAnuncio(
    Uint8List imagen, {
    int? dias,
    String titulo = '',
    String detalle = '',
    String whatsapp = '',
    String instagram = '',
  }) async {
    final url = await _subirAnuncio(imagen);
    await _firestore.collection('anuncios').add({
      'imagenUrl': url,
      'titulo': titulo,
      'detalle': detalle,
      'whatsapp': whatsapp,
      'instagram': instagram,
      'creadoPor': FirebaseAuth.instance.currentUser?.uid,
      'creadoEn': FieldValue.serverTimestamp(),
      'venceEn': dias == null ? null : _vence(dias),
    });
  }

  @override
  Future<void> actualizarAnuncio(
    Anuncio anuncio, {
    required String titulo,
    required String detalle,
    required String whatsapp,
    required String instagram,
    int? dias,
    Uint8List? nuevaImagen,
  }) async {
    final url = nuevaImagen == null
        ? anuncio.imagenUrl
        : await _subirAnuncio(nuevaImagen);
    await _firestore.collection('anuncios').doc(anuncio.id).update({
      'imagenUrl': url,
      'titulo': titulo,
      'detalle': detalle,
      'whatsapp': whatsapp,
      'instagram': instagram,
      if (dias != null) 'venceEn': dias == 0 ? null : _vence(dias),
      'editadoEn': FieldValue.serverTimestamp(),
    });
    if (url != anuncio.imagenUrl) {
      await _imagenes.deleteByUrl(anuncio.imagenUrl);
    }
  }

  @override
  Future<void> eliminarAnuncio(Anuncio anuncio) async {
    await _firestore.collection('anuncios').doc(anuncio.id).delete();
    // Best-effort: si la subió otro admin, Storage no deja borrarla y queda
    // huérfana (no se ve en ningún lado).
    await _imagenes.deleteByUrl(anuncio.imagenUrl);
  }

  static Promocion _promocionDe(String id, Map<String, dynamic> data) =>
      Promocion(
        id: id,
        titulo: '${data['titulo'] ?? ''}',
        cuerpo: '${data['cuerpo'] ?? ''}',
        imagenUrl: '${data['imagenUrl'] ?? ''}',
        audiencia: AudienciaPromocion.values.firstWhere(
          (a) => a.name == data['audiencia'],
          orElse: () => AudienciaPromocion.todos,
        ),
        venceEn: (data['venceEn'] as Timestamp?)?.toDate(),
        creadoEn: (data['creadoEn'] as Timestamp?)?.toDate(),
      );

  @override
  Stream<List<Promocion>> watchPromociones({int limite = 50}) => _firestore
      .collection('promociones')
      .orderBy('creadoEn', descending: true)
      .limit(limite)
      .snapshots()
      .map(
        (snap) => snap.docs.map((d) => _promocionDe(d.id, d.data())).toList(),
      );

  @override
  Future<Promocion?> obtenerPromocion(String id) async {
    final doc = await _firestore.collection('promociones').doc(id).get();
    final data = doc.data();
    return data == null ? null : _promocionDe(doc.id, data);
  }

  @override
  Future<void> enviarPromocion({
    required String titulo,
    required String cuerpo,
    required AudienciaPromocion audiencia,
    required int diasVigencia,
    Uint8List? imagen,
  }) async {
    final url = imagen == null ? '' : await _subirPromocion(imagen);
    await FirebaseFunctions.instance.httpsCallable('enviarPromocion').call({
      'titulo': titulo,
      'cuerpo': cuerpo,
      'imagenUrl': url,
      'audiencia': audiencia.name,
      'diasVigencia': diasVigencia,
    });
  }

  @override
  Future<void> actualizarPromocion(
    Promocion promo, {
    required String titulo,
    required String cuerpo,
    required AudienciaPromocion audiencia,
    int? dias,
    Uint8List? nuevaImagen,
    bool quitarImagen = false,
  }) async {
    var url = promo.imagenUrl;
    if (nuevaImagen != null) {
      url = await _subirPromocion(nuevaImagen);
    } else if (quitarImagen) {
      url = '';
    }
    await _firestore.collection('promociones').doc(promo.id).update({
      'titulo': titulo,
      'cuerpo': cuerpo,
      'audiencia': audiencia.name,
      'imagenUrl': url,
      if (dias != null)
        'venceEn': Timestamp.fromDate(DateTime.now().add(Duration(days: dias))),
      'editadoEn': FieldValue.serverTimestamp(),
    });
    // La imagen vieja ya no la usa nadie (best-effort).
    if (url != promo.imagenUrl) await _imagenes.deleteByUrl(promo.imagenUrl);
  }

  @override
  Future<void> eliminarPromocion(Promocion promo) async {
    await _firestore.collection('promociones').doc(promo.id).delete();
    await _imagenes.deleteByUrl(promo.imagenUrl);
  }

  static const String _clavePromosVistas = 'promociones_vistas';

  @override
  Future<Set<String>> promocionesVistas() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_clavePromosVistas) ?? const []).toSet();
  }

  @override
  Future<void> marcarPromocionVista(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final vistas = prefs.getStringList(_clavePromosVistas) ?? <String>[];
    if (vistas.contains(id)) return;
    vistas.add(id);
    // Solo importan las recientes: el inicio mira las últimas 5.
    await prefs.setStringList(
      _clavePromosVistas,
      vistas.length > 30 ? vistas.sublist(vistas.length - 30) : vistas,
    );
  }
}
