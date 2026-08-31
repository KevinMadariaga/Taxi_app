import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/get_client_user_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/complete_client_profile_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/controladores/complete_profile_controller.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';

/// Registro / completar perfil del cliente (Google / Apple).
/// Prefijado con el nombre del proveedor cuando lo entrega. La foto es
/// obligatoria: ni Google ni Apple la guardan en `usuarios/{uid}` (ambos
/// usecases de sign-in pasan `photoUrl: null` a propósito — ver
/// `sign_in_apple_client_usecase.dart` / `sign_in_google_client_usecase.dart`),
/// así que un alta nueva siempre llega acá sin foto previa.
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
  late final FocusNode _nombreFocusNode;
  late final FocusNode _apellidoFocusNode;
  late final FocusNode _correoFocusNode;
  late final FocusNode _telefonoFocusNode;

  bool _hydratedFromData = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.initialNombre ?? '');
    _apellidoController = TextEditingController(
      text: widget.initialApellido ?? '',
    );
    _correoController = TextEditingController(text: widget.initialCorreo ?? '');
    _telefonoController = TextEditingController(
      text: _normalizeToTenDigits(widget.initialTelefono),
    );
    _nombreFocusNode = FocusNode();
    _apellidoFocusNode = FocusNode();
    _correoFocusNode = FocusNode();
    _telefonoFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _nombreFocusNode.dispose();
    _apellidoFocusNode.dispose();
    _correoFocusNode.dispose();
    _telefonoFocusNode.dispose();
    super.dispose();
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
          _hydrateFieldsFromRemote(vm);

          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              title: const Text(
                'Completa tu perfil',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            body: vm.loadingInitial
                ? const Center(child: CircularProgressIndicator())
                : SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: _buildForm(context, vm),
                              ),
                            ),
                          ),
                        ),
                        _buildBottomBar(context, vm),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, CompleteProfileController vm) {
    final file = vm.selectedImage != null ? File(vm.selectedImage!.path) : null;
    // Una foto ya guardada en `usuarios/{uid}.foto` (de un intento anterior
    // de completar el perfil, nunca del proveedor Google/Apple — ninguno de
    // los dos la entrega) cuenta como válida: es lo que `saveProfile`
    // acepta cuando no se pudo tomar una nueva.
    final fotoPreviaUrl = vm.tieneFotoPrevia ? vm.currentUser?.fotoUrl : null;
    final tieneFoto = file != null || fotoPreviaUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Text(
          '¡Casi listo! 🎉',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: AppColores.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Confirma tus datos para empezar a pedir viajes.',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.35,
            color: AppColores.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: _AvatarPicker(
            selectedFile: file,
            networkUrl: fotoPreviaUrl,
            enabled: !vm.saving,
            onTap: () => vm.pickProfileImage(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tieneFoto
              ? 'Toca para cambiar la foto'
              : 'Toma tu foto de perfil (obligatorio)',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: tieneFoto ? AppColores.textSecondary : AppColores.error,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        _LabeledField(
          label: 'Nombre',
          controller: _nombreController,
          focusNode: _nombreFocusNode,
          enabled: !vm.saving,
          icon: Icons.person_outline_rounded,
          hint: 'Tu nombre',
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _apellidoFocusNode.requestFocus(),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Apellido',
          controller: _apellidoController,
          focusNode: _apellidoFocusNode,
          enabled: !vm.saving,
          icon: Icons.badge_outlined,
          hint: 'Tu apellido',
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _correoFocusNode.requestFocus(),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Correo electrónico',
          controller: _correoController,
          focusNode: _correoFocusNode,
          enabled: false,
          icon: Icons.email_outlined,
          hint: 'Tu correo',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _telefonoFocusNode.requestFocus(),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Teléfono',
          controller: _telefonoController,
          focusNode: _telefonoFocusNode,
          enabled: !vm.saving,
          icon: Icons.phone_outlined,
          hint: '10 dígitos',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        if (_formError != null || vm.errorMessage != null) ...[
          const SizedBox(height: 18),
          _InlineError(message: _formError ?? vm.errorMessage!),
        ],
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, CompleteProfileController vm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
      decoration: BoxDecoration(
        color: AppColores.background,
        border: Border(top: BorderSide(color: AppColores.borderSubtle)),
      ),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: vm.saving ? null : () => _submit(context, vm),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColores.buttonPrimary,
            foregroundColor: AppColores.textWhite,
            disabledBackgroundColor: AppColores.buttonPrimary.withValues(
              alpha: 0.6,
            ),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: vm.saving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColores.textWhite,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Guardar datos',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
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
      _telefonoController.text = _normalizeToTenDigits(user.telefono);
    }
    _hydratedFromData = true;
  }

  Future<void> _submit(
    BuildContext context,
    CompleteProfileController vm,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);

    final resolvedPhone = _resolvePhoneForSubmit(vm);
    final error = await vm.saveProfile(
      nombre: _nombreController.text,
      apellido: _apellidoController.text,
      correo: _correoController.text,
      telefono: resolvedPhone,
      requireTelefono: true,
    );

    if (!context.mounted) return;

    if (error != null) {
      setState(() => _formError = error);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sus datos han sido guardados.'),
        backgroundColor: AppColores.success,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeClienteView(authUid: widget.uid)),
      (route) => false,
    );
  }

  String _resolvePhoneForSubmit(CompleteProfileController vm) {
    final fromInput = _normalizeToTenDigits(_telefonoController.text);
    if (fromInput.isNotEmpty) return fromInput;
    final fromUser = _normalizeToTenDigits(vm.currentUser?.telefono);
    if (fromUser.isNotEmpty) return fromUser;
    return _normalizeToTenDigits(widget.initialTelefono);
  }

  String _normalizeToTenDigits(String? input) {
    final digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.selectedFile,
    required this.networkUrl,
    required this.enabled,
    required this.onTap,
  });

  final File? selectedFile;
  final String? networkUrl;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (selectedFile != null) {
      image = FileImage(selectedFile!);
    } else if ((networkUrl ?? '').isNotEmpty) {
      image = NetworkImage(networkUrl!);
    }

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Stack(
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColores.primary.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColores.primary.withValues(alpha: 0.35),
                width: 2,
              ),
              image: image != null
                  ? DecorationImage(image: image, fit: BoxFit.cover)
                  : null,
            ),
            child: image == null
                ? Icon(
                    Icons.person_rounded,
                    size: 54,
                    color: AppColores.primary.withValues(alpha: 0.55),
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColores.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColores.background, width: 3),
              ),
              child: const Icon(
                Icons.photo_camera_rounded,
                size: 17,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.icon,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final IconData icon;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColores.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: AppColores.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColores.textSecondary,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(icon, color: AppColores.textSecondary, size: 21),
            filled: true,
            fillColor: AppColores.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColores.grey300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColores.primary,
                width: 1.6,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColores.grey200),
            ),
          ),
        ),
      ],
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
        color: AppColores.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColores.error.withValues(alpha: 0.30)),
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
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColores.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
