import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/services/face_detection_service.dart';
import 'package:taxi_app/core/services/image_cropper_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/widgets/flip_preview_view.dart';
import 'package:taxi_app/widgets/elegir_origen_imagen_sheet.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/repositorios/client_auth_repository.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/client_auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/entidades/client_user_entity.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/validar_perfil_cliente.dart';
import 'package:taxi_app/core/services/services.dart';

class CompleteProfileController extends ChangeNotifier {
  CompleteProfileController({
    required this.uid,
    GetClientUserUseCase? getClientUserUseCase,
    CompleteClientProfileUseCase? completeClientProfileUseCase,
    ClientAuthRepository? clientAuthRepository,
    ImageCropperService? imageCropperService,
    ImagePicker? imagePicker,
    AuthService? authService,
    FaceDetectionService? faceDetectionService,
  }) : _faceDetectionInyectado = faceDetectionService,
       _getClientUserUseCase =
           getClientUserUseCase ??
           GetClientUserUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           ),
       _completeClientProfileUseCase =
           completeClientProfileUseCase ??
           CompleteClientProfileUseCase(
             clientAuthRepository ?? ClientAuthRepositoryImpl(),
           ),
       _imageCropperService =
           imageCropperService ?? const ImageCropperService(),
       _imagePicker = imagePicker ?? ImagePicker(),
       _authService = authService ?? AuthService();

  final String uid;
  final GetClientUserUseCase _getClientUserUseCase;
  final CompleteClientProfileUseCase _completeClientProfileUseCase;
  final ImageCropperService _imageCropperService;
  final ImagePicker _imagePicker;
  final AuthService _authService;

  // Perezoso: el detector de ML Kit solo se crea si el usuario elige una
  // foto, no al abrir la pantalla.
  final FaceDetectionService? _faceDetectionInyectado;
  FaceDetectionService? _faceDetection;
  FaceDetectionService get _detector =>
      _faceDetection ??= _faceDetectionInyectado ?? FaceDetectionService();

  bool _validandoRostro = false;
  bool get validandoRostro => _validandoRostro;

  ClientUserEntity? _currentUser;
  XFile? _selectedImage;
  bool _loadingInitial = true;
  bool _saving = false;
  String? _errorMessage;

  ClientUserEntity? get currentUser => _currentUser;
  XFile? get selectedImage => _selectedImage;
  bool get loadingInitial => _loadingInitial;
  bool get saving => _saving;
  String? get errorMessage => _errorMessage;

  /// Errores del último formulario validado. Un campo solo muestra el suyo
  /// cuando el usuario ya pasó por él (salió del campo) o intentó enviar:
  /// no se pinta todo en rojo apenas se abre la pantalla.
  Map<CampoPerfil, ErrorCampo> _errores = const {};
  final Set<CampoPerfil> _visibles = {};
  int _intentosFallidos = 0;

  String? errorDe(CampoPerfil campo) =>
      _visibles.contains(campo) ? _errores[campo]?.mensaje : null;

  /// Cambia en cada envío rechazado: la vista lo usa para sacudir los
  /// campos con error aunque sean los mismos que la vez anterior.
  int get intentosFallidos => _intentosFallidos;

  bool get tieneFoto => _selectedImage != null || tieneFotoPrevia;

  /// Pasos del registro y los campos que valida cada uno, en orden.
  static const List<List<CampoPerfil>> pasos = [
    [CampoPerfil.nombre, CampoPerfil.apellido],
    [CampoPerfil.telefono],
    [CampoPerfil.foto],
  ];

  int _paso = 0;
  int get paso => _paso;
  bool get esUltimoPaso => _paso == pasos.length - 1;

  static int _pasoDe(CampoPerfil campo) =>
      pasos.indexWhere((campos) => campos.contains(campo));

  /// Valida solo los campos del paso actual. Si están bien pasa al
  /// siguiente y devuelve `null`; si no, deja sus errores a la vista y
  /// devuelve el primer campo a corregir.
  CampoPerfil? avanzar(PerfilFormulario f) {
    final errores = validarPerfilCliente(f);
    final pendientes = pasos[_paso].where(errores.containsKey);
    if (pendientes.isNotEmpty) {
      _errores = errores;
      _visibles.addAll(pasos[_paso]);
      _intentosFallidos++;
      _safeNotify();
      return pendientes.first;
    }
    if (!esUltimoPaso) {
      _paso++;
      _safeNotify();
    }
    return null;
  }

  /// Vuelve al paso anterior; `false` si ya está en el primero.
  bool retroceder() {
    if (_paso == 0 || _saving) return false;
    _paso--;
    _safeNotify();
    return true;
  }

  /// Campos que ya están bien (progreso y check verde de cada campo).
  Set<CampoPerfil> camposValidos(PerfilFormulario f) {
    final errores = validarPerfilCliente(f);
    return CampoPerfil.values.where((c) => !errores.containsKey(c)).toSet();
  }

  /// El usuario salió de [campo]: a partir de acá se le muestra su error.
  void marcarVisitado(CampoPerfil campo, PerfilFormulario f) {
    _visibles.add(campo);
    revalidar(f);
  }

  /// Revalida en vivo (al escribir) solo si ya hay algún error a la vista,
  /// para que el mensaje desaparezca apenas se corrige.
  void revalidar(PerfilFormulario f) {
    if (_visibles.isEmpty) return;
    _errores = validarPerfilCliente(f);
    _safeNotify();
  }

  Future<void> loadInitialData() async {
    _loadingInitial = true;
    _errorMessage = null;
    _safeNotify();

    try {
      _currentUser = await _getClientUserUseCase(uid);
    } catch (_) {
      _errorMessage = 'No fue posible cargar la informacion inicial.';
    } finally {
      _loadingInitial = false;
      _safeNotify();
    }
  }

  /// Toma o elige la foto de perfil (cámara o galería, a elección del
  /// usuario).
  ///
  /// Va envuelto en try/catch porque se invoca fire-and-forget desde el `onTap`
  /// del avatar: sin captura, un `PlatformException` (permiso denegado —
  /// que esta app nunca solicita explícitamente —, equipo sin cámara, o
  /// fallo del cropper) se convertía en un error async sin manejar y al
  /// usuario **no le pasaba absolutamente nada** al tocar el avatar,
  /// dejándolo atrapado en "Completa tu perfil" sin mensaje ni salida.
  Future<void> pickProfileImage(BuildContext context) async {
    try {
      final origen = await mostrarElegirOrigenImagen(context);
      if (origen == null) return;

      if (!context.mounted) return;
      final picked = await _imagePicker.pickImage(
        source: origen,
        imageQuality: 100,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (picked == null) return;

      File sourceFile = File(picked.path);

      // Antes del flip/crop, para no hacer recortar una foto que igual se
      // va a rechazar.
      if (!await _tieneRostro(sourceFile.path)) return;

      // El "voltear" corrige el espejado que aplica la cámara frontal — no
      // aplica a una foto ya elegida de galería.
      if (origen == ImageSource.camera) {
        if (!context.mounted) return;
        final flipped = await showFlipPreview(context, imageFile: sourceFile);
        if (flipped == null) return;
        sourceFile = flipped;
      }

      final cropped = await _imageCropperService.cropProfileImage(
        sourcePath: sourceFile.path,
      );
      if (cropped == null) return;

      // Y otra vez sobre el recorte, que es lo que se sube: el usuario pudo
      // haber dejado la cara fuera del cuadro.
      if (!await _tieneRostro(cropped.path)) return;

      _selectedImage = XFile(cropped.path);
      _errorMessage = null;
      _errores = Map.of(_errores)..remove(CampoPerfil.foto);
      _safeNotify();
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'complete_profile_controller');
      _errorMessage = tieneFotoPrevia
          ? 'No se pudo obtener la foto. Puedes continuar con tu foto actual.'
          : 'No se pudo obtener la foto. Revisa los permisos de la app e '
                'intenta de nuevo.';
      _safeNotify();
    }
  }

  /// `false` (y deja el error bajo la foto) si no se ve un rostro. Si el
  /// detector falla, `FaceDetectionService.hasFace` deja pasar la foto: un
  /// fallo del modelo no debe dejar al usuario sin poder registrarse.
  Future<bool> _tieneRostro(String path) async {
    _validandoRostro = true;
    _safeNotify();
    try {
      final ok = await _detector.hasFace(path);
      if (!ok) {
        _errores = {
          ..._errores,
          CampoPerfil.foto: const ErrorCampo(
            'No se ve un rostro en la foto. Usa una foto tuya, de frente '
            'y con buena luz.',
            vacio: false,
          ),
        };
        _visibles.add(CampoPerfil.foto);
      }
      return ok;
    } finally {
      _validandoRostro = false;
      _safeNotify();
    }
  }

  /// `true` si el usuario ya tiene una foto guardada en `usuarios/{uid}.foto`
  /// de un intento anterior de completar el perfil, en cuyo caso no hace
  /// falta tomar una nueva. Nunca viene del proveedor: ni Google ni Apple
  /// entregan foto en el sign-in (ambos usecases pasan `photoUrl: null` a
  /// propósito), así que en un alta nueva esto siempre es `false`.
  bool get tieneFotoPrevia => (_currentUser?.fotoUrl ?? '').trim().isNotEmpty;

  Future<String?> saveProfile({
    required String nombre,
    required String apellido,
    required String telefono,
    String? correo,
    bool requireTelefono = true,
  }) async {
    var telefonoNormalizado = normalizarTelefono10(telefono);
    if (telefonoNormalizado.isEmpty) {
      telefonoNormalizado = normalizarTelefono10(_currentUser?.telefono);
    }

    // Solo se exige foto nueva si el usuario tampoco tiene una previa
    // guardada en Firestore (ver `tieneFotoPrevia`). En un alta nueva con
    // Google/Apple eso nunca ocurre — ninguno de los dos entrega foto en el
    // sign-in — así que la foto es obligatoria de facto ahí. Este escape
    // existe para quien ya completó el perfil una vez y vuelve a pasar por
    // acá sin poder usar la cámara (permiso denegado, equipo sin cámara):
    // no queda encerrado si ya tiene una foto válida guardada.
    final errores = validarPerfilCliente(
      PerfilFormulario(
        nombre: nombre,
        apellido: apellido,
        telefono: telefonoNormalizado,
        tieneFoto: tieneFoto,
      ),
    );
    if (!requireTelefono && telefonoNormalizado.isEmpty) {
      return 'No se pudo recuperar el telefono de verificacion.';
    }
    if (!requireTelefono) errores.remove(CampoPerfil.telefono);
    if (errores.isNotEmpty) {
      _errores = errores;
      _visibles.addAll(CampoPerfil.values);
      _intentosFallidos++;
      // Lleva al paso del primer dato que falta (ej. el teléfono de la
      // cuenta cambió entre pasos).
      _paso = _pasoDe(CampoPerfil.values.firstWhere(errores.containsKey));
      _safeNotify();
      return mensajeResumenPerfil(errores);
    }

    _saving = true;
    _errorMessage = null;
    _safeNotify();

    try {
      final updated = await _completeClientProfileUseCase(
        CompleteClientProfileParams(
          uid: uid,
          nombre: nombre.trim(),
          apellido: apellido.trim(),
          telefono: telefonoNormalizado,
          profileImageFile: _selectedImage != null
              ? File(_selectedImage!.path)
              : null,
          email: correo?.trim().isNotEmpty == true ? correo!.trim() : null,
        ),
      );

      _currentUser = updated;
      await _authService.saveUserSession(role: 'cliente', isLoggedIn: true);
      await _authService.marcarPerfilCompleto();

      return null;
    } catch (error) {
      _errorMessage = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('Exception: ', '')
          .trim();
      return _errorMessage;
    } finally {
      _saving = false;
      _safeNotify();
    }
  }

  // Antes este controller llamaba `notifyListeners()` directo en sus 6
  // sitios: lo destruye el `ChangeNotifierProvider` de
  // `complete_profile_page.dart`, y `await _imageCropperService
  // .cropProfileImage(...)` abre UI nativa que puede tardar minutos — si el
  // usuario sale de la pantalla mientras tanto, el notify que llega después
  // revienta con "used after being disposed" (auditoría de bugs). Mismo
  // patrón `_disposed` + `_safeNotify()` que ya usan `BuscandoTaxiViewModel`,
  // `ViajeClienteViewModel`, `ViajeConductorViewModel`,
  // `SeleccionDestinoViewModel` y `ConfirmarSolicitudViewModel`.
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Solo el que creó el controller; uno inyectado lo cierra su dueño.
    if (_faceDetectionInyectado == null) _faceDetection?.dispose();
    super.dispose();
  }
}
