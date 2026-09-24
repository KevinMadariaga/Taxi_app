import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/validar_perfil_cliente.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/controladores/complete_profile_controller.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/widgets/intermediate_transition_view.dart';

/// Registro / completar perfil del cliente (Google / Apple), en tres pasos:
/// nombre y apellido → celular → foto. Prefijado con el nombre del proveedor
/// cuando lo entrega. La foto es obligatoria: ni Google ni Apple la guardan
/// en `usuarios/{uid}` (ambos usecases de sign-in pasan `photoUrl: null` a
/// propósito — ver `sign_in_apple_client_usecase.dart` /
/// `sign_in_google_client_usecase.dart`), así que un alta nueva siempre
/// llega acá sin foto previa.
///
/// Sin AppBar de color: el naranja de marca queda solo en lo accionable
/// (foco, botón, progreso). Una barra naranja fija competía con el botón
/// principal y en modo oscuro era el único bloque claro de la pantalla.
class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({
    super.key,
    required this.uid,
    this.initialNombre,
    this.initialApellido,
    this.initialTelefono,
    this.initialCorreo,
  });

  final String uid;
  final String? initialNombre;
  final String? initialApellido;
  final String? initialTelefono;
  final String? initialCorreo;

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  late final TextEditingController _nombreController;
  late final TextEditingController _apellidoController;
  late final TextEditingController _correoController;
  late final TextEditingController _telefonoController;
  late final Map<CampoPerfil, FocusNode> _focos;

  CompleteProfileController? _vm;
  bool _hydratedFromData = false;
  String? _formError;

  /// Paso mostrado en el frame anterior: decide si la transición entra por
  /// la derecha (avanzar) o por la izquierda (volver).
  int _pasoAnterior = 0;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.initialNombre ?? '');
    _apellidoController = TextEditingController(
      text: widget.initialApellido ?? '',
    );
    _correoController = TextEditingController(text: widget.initialCorreo ?? '');
    _telefonoController = TextEditingController(
      text: normalizarTelefono10(widget.initialTelefono),
    );
    _focos = {
      for (final c in [
        CampoPerfil.nombre,
        CampoPerfil.apellido,
        CampoPerfil.telefono,
      ])
        c: FocusNode()..addListener(() => _alCambiarFoco(c)),
    };
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  PerfilFormulario _formulario(CompleteProfileController vm) =>
      PerfilFormulario(
        nombre: _nombreController.text,
        apellido: _apellidoController.text,
        telefono: _resolvePhoneForSubmit(vm),
        tieneFoto: vm.tieneFoto,
      );

  void _alCambiarFoco(CampoPerfil campo) {
    final vm = _vm;
    if (vm == null || _focos[campo]!.hasFocus) return;
    vm.marcarVisitado(campo, _formulario(vm));
  }

  void _alEscribir() {
    final vm = _vm;
    if (vm == null) return;
    if (_formError != null) setState(() => _formError = null);
    vm.revalidar(_formulario(vm));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CompleteProfileController>(
      create: (context) {
        try {
          return CompleteProfileController(
            uid: widget.uid,
            getClientUserUseCase: Provider.of<GetClientUserUseCase>(
              context,
              listen: false,
            ),
            completeClientProfileUseCase:
                Provider.of<CompleteClientProfileUseCase>(
                  context,
                  listen: false,
                ),
          )..loadInitialData();
        } catch (_) {
          return CompleteProfileController(uid: widget.uid)..loadInitialData();
        }
      },
      child: Consumer<CompleteProfileController>(
        builder: (context, vm, _) {
          _vm = vm;
          _hydrateFieldsFromRemote(vm);
          final palette = context.palette;
          final esOscuro = Theme.of(context).brightness == Brightness.dark;
          final avanza = vm.paso >= _pasoAnterior;
          _pasoAnterior = vm.paso;

          return PopScope(
            // Atrás (gesto o botón del sistema) vuelve un paso; solo en el
            // primero sale de la pantalla.
            canPop: vm.paso == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _retroceder(vm);
            },
            child: Scaffold(
              backgroundColor: palette.background,
              appBar: AppBar(
                backgroundColor: palette.background,
                foregroundColor: palette.textPrimary,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                systemOverlayStyle: esOscuro
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                leading: vm.paso > 0
                    ? IconButton(
                        tooltip: 'Paso anterior',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: vm.saving ? null : () => _retroceder(vm),
                      )
                    : null,
                title: _ProgresoPasos(
                  paso: vm.paso,
                  total: CompleteProfileController.pasos.length,
                ),
                titleSpacing: vm.paso > 0 ? 0 : null,
                actions: const [SizedBox(width: 20)],
              ),
              body: vm.loadingInitial
                  ? const Center(child: CircularProgressIndicator())
                  : SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, anim) {
                                final entra = child.key == ValueKey(vm.paso);
                                final desde = (entra == avanza) ? 0.25 : -0.25;
                                return FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: Offset(desde, 0),
                                      end: Offset.zero,
                                    ).animate(anim),
                                    child: child,
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey(vm.paso),
                                child: _buildScroll(context, vm),
                              ),
                            ),
                          ),
                          _buildBottomBar(context, vm),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScroll(BuildContext context, CompleteProfileController vm) {
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.06 : 32.0;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: esMovil ? 520 : 560),
          child: switch (vm.paso) {
            0 => _pasoNombre(context, vm, esMovil),
            1 => _pasoTelefono(context, vm, esMovil),
            _ => _pasoFoto(context, vm, esMovil),
          },
        ),
      ),
    );
  }

  Widget _paso({
    required bool esMovil,
    required IconData icono,
    required String titulo,
    required String descripcion,
    required List<Widget> contenido,
  }) {
    var orden = 0;
    Widget aparecer(Widget child) => _Aparecer(orden: orden++, child: child);
    final banner = _formError ?? _vm?.errorMessage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        aparecer(
          _EncabezadoPaso(
            icono: icono,
            titulo: titulo,
            descripcion: descripcion,
            esMovil: esMovil,
          ),
        ),
        SizedBox(height: esMovil ? 26 : 32),
        for (final w in contenido) aparecer(w),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: banner == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: _InlineError(message: banner),
                ),
        ),
      ],
    );
  }

  Widget _pasoNombre(
    BuildContext context,
    CompleteProfileController vm,
    bool esMovil,
  ) {
    final validos = vm.camposValidos(_formulario(vm));
    final correo = _correoController.text.trim();
    return _paso(
      esMovil: esMovil,
      icono: Icons.waving_hand_rounded,
      titulo: '¿Cómo te llamas?',
      descripcion:
          'Así te verá el conductor cuando acepte tu viaje. Escríbelos como '
          'aparecen en tu documento.',
      contenido: [
        _CampoTexto(
          label: 'Nombre',
          descripcion:
              'Tu primer nombre, o los dos si así te conocen. '
              'Solo letras.',
          controller: _nombreController,
          focusNode: _focos[CampoPerfil.nombre]!,
          enabled: !vm.saving,
          icon: Icons.person_outline_rounded,
          hint: 'Ej. Laura',
          error: vm.errorDe(CampoPerfil.nombre),
          valido: validos.contains(CampoPerfil.nombre),
          disparador: vm.intentosFallidos,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          onChanged: (_) => _alEscribir(),
          onSubmitted: (_) => _focos[CampoPerfil.apellido]!.requestFocus(),
        ),
        const SizedBox(height: 18),
        _CampoTexto(
          label: 'Apellido',
          descripcion: 'Tu primer apellido. Solo letras.',
          controller: _apellidoController,
          focusNode: _focos[CampoPerfil.apellido]!,
          enabled: !vm.saving,
          icon: Icons.badge_outlined,
          hint: 'Ej. Gómez',
          error: vm.errorDe(CampoPerfil.apellido),
          valido: validos.contains(CampoPerfil.apellido),
          disparador: vm.intentosFallidos,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [LengthLimitingTextInputFormatter(40)],
          onChanged: (_) => _alEscribir(),
          onSubmitted: (_) => _continuar(context, vm),
        ),
        // El correo lo entrega el proveedor y no se edita: solo se muestra
        // cuando existe (Apple puede no entregarlo).
        if (correo.isNotEmpty) ...[
          const SizedBox(height: 18),
          _CorreoSoloLectura(correo: correo),
        ],
      ],
    );
  }

  Widget _pasoTelefono(
    BuildContext context,
    CompleteProfileController vm,
    bool esMovil,
  ) {
    return _paso(
      esMovil: esMovil,
      icono: Icons.phone_iphone_rounded,
      titulo: 'Tu número de celular',
      descripcion:
          'El conductor podrá llamarte si no te encuentra en el punto de '
          'recogida. No lo compartimos con nadie más.',
      contenido: [
        _CampoTexto(
          label: 'Celular',
          descripcion: '10 dígitos, sin el +57 ni espacios. Ej. 3001234567.',
          controller: _telefonoController,
          focusNode: _focos[CampoPerfil.telefono]!,
          enabled: !vm.saving,
          icon: Icons.phone_iphone_rounded,
          hint: '300 123 4567',
          prefijo: '+57',
          error: vm.errorDe(CampoPerfil.telefono),
          valido: vm
              .camposValidos(_formulario(vm))
              .contains(CampoPerfil.telefono),
          disparador: vm.intentosFallidos,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onChanged: (_) => _alEscribir(),
          onSubmitted: (_) => _continuar(context, vm),
        ),
      ],
    );
  }

  Widget _pasoFoto(
    BuildContext context,
    CompleteProfileController vm,
    bool esMovil,
  ) {
    final palette = context.palette;
    final file = vm.selectedImage != null ? File(vm.selectedImage!.path) : null;
    // Una foto ya guardada en `usuarios/{uid}.foto` (de un intento anterior
    // de completar el perfil, nunca del proveedor Google/Apple — ninguno de
    // los dos la entrega) cuenta como válida: es lo que `saveProfile`
    // acepta cuando no se pudo tomar una nueva.
    final fotoPreviaUrl = vm.tieneFotoPrevia ? vm.currentUser?.fotoUrl : null;
    final fotoError = vm.errorDe(CampoPerfil.foto);

    return _paso(
      esMovil: esMovil,
      icono: Icons.face_retouching_natural_rounded,
      titulo: 'Tu foto de perfil',
      descripcion:
          'El conductor la verá para reconocerte al recogerte. Usa una foto '
          'tuya, de frente, con buena luz y sin gafas oscuras ni gorra.',
      contenido: [
        _Sacudir(
          activo: fotoError != null,
          disparador: vm.intentosFallidos,
          child: Column(
            children: [
              _AvatarPicker(
                selectedFile: file,
                networkUrl: fotoPreviaUrl,
                enabled: !vm.saving && !vm.validandoRostro,
                validando: vm.validandoRostro,
                conError: fotoError != null,
                size: esMovil ? 150 : 170,
                onTap: () => vm.pickProfileImage(context),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  fotoError ??
                      (vm.validandoRostro
                          ? 'Verificando tu rostro…'
                          : vm.tieneFoto
                          ? 'Toca la foto para cambiarla'
                          : 'Toca el círculo para tomar o elegir tu foto'),
                  key: ValueKey(
                    fotoError ?? '${vm.tieneFoto}${vm.validandoRostro}',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fotoError != null
                        ? AppColores.error
                        : palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _ConsejosFoto(),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, CompleteProfileController vm) {
    final palette = context.palette;
    final resp = ResponsiveHelper.getResponsiveData(context);
    final esMovil = resp.deviceType == DeviceType.mobile;
    final horizontal = esMovil ? resp.screenWidth * 0.06 : 32.0;
    final ultimo = vm.esUltimoPaso;

    return Container(
      padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 14),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: esMovil ? 520 : 560),
          child: SizedBox(
            width: double.infinity,
            height: esMovil ? 54 : 58,
            child: ElevatedButton(
              onPressed: vm.saving || vm.validandoRostro
                  ? null
                  : () => _continuar(context, vm),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColores.buttonPrimary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColores.buttonPrimary.withValues(
                  alpha: 0.6,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: vm.saving
                    ? const SizedBox(
                        key: ValueKey('cargando'),
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.black,
                        ),
                      )
                    : FittedBox(
                        key: ValueKey(ultimo),
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ultimo ? 'Crear mi cuenta' : 'Continuar',
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              ultimo
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _hydrateFieldsFromRemote(CompleteProfileController vm) {
    if (_hydratedFromData) return;
    final user = vm.currentUser;
    if (user == null) return;

    if (_nombreController.text.trim().isEmpty &&
        user.nombre.trim().isNotEmpty) {
      _nombreController.text = user.nombre.trim();
    }
    if (_apellidoController.text.trim().isEmpty &&
        user.apellido.trim().isNotEmpty) {
      _apellidoController.text = user.apellido.trim();
    }
    if (_correoController.text.trim().isEmpty &&
        (user.email ?? '').trim().isNotEmpty) {
      _correoController.text = user.email!.trim();
    }
    if (_telefonoController.text.trim().isEmpty &&
        user.telefono.trim().isNotEmpty) {
      _telefonoController.text = normalizarTelefono10(user.telefono);
    }
    _hydratedFromData = true;
  }

  void _retroceder(CompleteProfileController vm) {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    vm.retroceder();
  }

  /// "Continuar" en los pasos 1-2; "Crear mi cuenta" en el último.
  Future<void> _continuar(
    BuildContext context,
    CompleteProfileController vm,
  ) async {
    setState(() => _formError = null);

    if (!vm.esUltimoPaso) {
      final pendiente = vm.avanzar(_formulario(vm));
      if (pendiente != null) {
        HapticFeedback.mediumImpact();
        _focos[pendiente]?.requestFocus();
        return;
      }
      FocusScope.of(context).unfocus();
      // El celular se escribe apenas entra el paso: se abre el teclado solo
      // cuando la transición ya terminó, para no cortarla.
      if (vm.paso == 1) {
        Future.delayed(const Duration(milliseconds: 340), () {
          if (mounted) _focos[CampoPerfil.telefono]!.requestFocus();
        });
      }
      return;
    }

    FocusScope.of(context).unfocus();
    final error = await vm.saveProfile(
      nombre: _nombreController.text,
      apellido: _apellidoController.text,
      correo: _correoController.text,
      telefono: _resolvePhoneForSubmit(vm),
      requireTelefono: true,
    );

    if (!context.mounted) return;

    if (error != null) {
      HapticFeedback.mediumImpact();
      // Los errores de campo ya se ven en su paso (saveProfile lleva ahí);
      // el banner es para lo que no es de un campo (red, subida de foto).
      final esDeCampo = CampoPerfil.values.any((c) => vm.errorDe(c) != null);
      setState(() => _formError = esDeCampo ? null : error);
      return;
    }

    unawaited(
      navigateWithIntermediateLoader(
        context: context,
        title: 'Registro completado',
        subtitle: '¡Bienvenido a Ride!',
        icon: Icons.how_to_reg_rounded,
        delay: const Duration(milliseconds: 2200),
        clearStackOnNext: true,
        nextBuilder: (_) => HomeClienteView(authUid: widget.uid),
      ),
    );
  }

  String _resolvePhoneForSubmit(CompleteProfileController vm) {
    final fromInput = normalizarTelefono10(_telefonoController.text);
    if (fromInput.isNotEmpty) return fromInput;
    final fromUser = normalizarTelefono10(vm.currentUser?.telefono);
    if (fromUser.isNotEmpty) return fromUser;
    return normalizarTelefono10(widget.initialTelefono);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Barra de progreso segmentada del AppBar: un tramo por paso.
class _ProgresoPasos extends StatelessWidget {
  const _ProgresoPasos({required this.paso, required this.total});

  final int paso;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paso ${paso + 1} de $total',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: i <= paso ? 1 : 0),
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: palette.grey300,
                      color: AppColores.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EncabezadoPaso extends StatelessWidget {
  const _EncabezadoPaso({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.esMovil,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final bool esMovil;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColores.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icono, color: AppColores.primary, size: 26),
        ),
        const SizedBox(height: 16),
        Text(
          titulo,
          style: TextStyle(
            fontSize: esMovil ? 26 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          descripcion,
          style: TextStyle(
            fontSize: esMovil ? 14.5 : 16,
            height: 1.4,
            color: palette.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ConsejosFoto extends StatelessWidget {
  const _ConsejosFoto();

  static const _consejos = [
    (Icons.face_rounded, 'Solo tú en la foto, de frente'),
    (Icons.wb_sunny_outlined, 'Con buena luz, sin sombras en la cara'),
    (Icons.no_photography_outlined, 'Sin gafas oscuras, gorra ni filtros'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        children: [
          for (final (icono, texto) in _consejos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(icono, size: 20, color: AppColores.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texto,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.selectedFile,
    required this.networkUrl,
    required this.enabled,
    required this.validando,
    required this.conError,
    required this.size,
    required this.onTap,
  });

  final File? selectedFile;
  final String? networkUrl;
  final bool enabled;
  final bool validando;
  final bool conError;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    ImageProvider? image;
    if (selectedFile != null) {
      image = FileImage(selectedFile!);
    } else if ((networkUrl ?? '').isNotEmpty) {
      image = NetworkImage(networkUrl!);
    }
    final borde = conError
        ? AppColores.error
        : image != null
        ? AppColores.success
        : AppColores.primary.withValues(alpha: 0.5);

    return Semantics(
      button: true,
      label: image == null
          ? 'Agregar foto de perfil'
          : 'Cambiar foto de perfil',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size + 8,
          height: size + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: size + 8,
                height: size + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borde, width: 2.5),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Container(
                  key: ValueKey(image),
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColores.primary.withValues(alpha: 0.12),
                    image: image != null
                        ? DecorationImage(image: image, fit: BoxFit.cover)
                        : null,
                  ),
                  child: image == null
                      ? Icon(
                          Icons.add_a_photo_outlined,
                          size: size * 0.36,
                          color: AppColores.primary,
                        )
                      : null,
                ),
              ),
              if (validando)
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black45,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColores.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.background, width: 3),
                  ),
                  child: Icon(
                    image == null
                        ? Icons.photo_camera_rounded
                        : Icons.edit_rounded,
                    size: 17,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
    required this.label,
    required this.descripcion,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.icon,
    required this.hint,
    required this.error,
    required this.valido,
    required this.disparador,
    this.prefijo,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final String descripcion;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final IconData icon;
  final String hint;
  final String? error;
  final bool valido;
  final int disparador;
  final String? prefijo;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final palette = context.palette;
        final esOscuro = Theme.of(context).brightness == Brightness.dark;
        final enfocado = focusNode.hasFocus;
        final conError = error != null;
        // En oscuro el borde del campo en reposo (`grey300`) casi desaparece
        // contra `surface`; el foco necesita borde + halo para distinguirse.
        final colorAcento = conError ? AppColores.error : AppColores.primary;
        final colorBorde = conError
            ? AppColores.error
            : enfocado
            ? AppColores.primary
            : palette.grey300;

        return _Sacudir(
          activo: conError,
          disparador: disparador,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: conError
                      ? AppColores.error
                      : enfocado
                      ? (esOscuro ? AppColores.primary : palette.textPrimary)
                      : palette.textPrimary,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 3),
              Text(
                descripcion,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: enfocado
                      ? (esOscuro
                            ? Color.alphaBlend(
                                AppColores.primary.withValues(alpha: 0.06),
                                palette.surface,
                              )
                            : palette.surface)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorBorde,
                    width: enfocado || conError ? 1.8 : 1.2,
                  ),
                  boxShadow: [
                    if (enfocado)
                      BoxShadow(
                        color: colorAcento.withValues(
                          alpha: esOscuro ? 0.28 : 0.18,
                        ),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  textCapitalization: textCapitalization,
                  inputFormatters: inputFormatters,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: AppColores.primary,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: palette.textSecondary.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        icon,
                        key: ValueKey(enfocado || conError),
                        size: 21,
                        color: conError
                            ? AppColores.error
                            : enfocado
                            ? AppColores.primary
                            : palette.textSecondary,
                      ),
                    ),
                    prefixText: prefijo == null ? null : '$prefijo  ',
                    prefixStyle: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary,
                    ),
                    suffixIcon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: valido && !conError
                          ? const Icon(
                              Icons.check_circle_rounded,
                              key: ValueKey('ok'),
                              color: AppColores.success,
                              size: 21,
                            )
                          : const SizedBox.shrink(key: ValueKey('nada')),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: AppColores.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColores.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CorreoSoloLectura extends StatelessWidget {
  const _CorreoSoloLectura({required this.correo});

  final String correo;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: palette.grey100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.email_outlined, size: 21, color: palette.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Correo de tu cuenta',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  correo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 18, color: palette.grey400),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColores.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColores.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: AppColores.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrada escalonada: cada bloque sube y aparece un poco después del
/// anterior. Respeta "reducir movimiento" del sistema.
class _Aparecer extends StatelessWidget {
  const _Aparecer({required this.orden, required this.child});

  final int orden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    const pasoMs = 70;
    const duracionMs = 420;
    final inicio = orden * pasoMs;
    final total = inicio + duracionMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, t, child) {
        final local = Curves.easeOutCubic.transform(
          ((t * total - inicio) / duracionMs).clamp(0.0, 1.0),
        );
        return Opacity(
          opacity: local,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - local)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Sacude horizontalmente a [child] cada vez que cambia [disparador]
/// mientras [activo] (el campo tiene error): marca qué falta al tocar
/// "Crear mi cuenta".
class _Sacudir extends StatefulWidget {
  const _Sacudir({
    required this.activo,
    required this.disparador,
    required this.child,
  });

  final bool activo;
  final int disparador;
  final Widget child;

  @override
  State<_Sacudir> createState() => _SacudirState();
}

class _SacudirState extends State<_Sacudir>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Sacudir old) {
    super.didUpdateWidget(old);
    if (widget.activo &&
        widget.disparador != old.disparador &&
        !MediaQuery.of(context).disableAnimations) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final dx = math.sin(_ctrl.value * math.pi * 4) * 8 * (1 - _ctrl.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}
