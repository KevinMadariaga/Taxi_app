import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/domain/usecases/client_auth/get_client_user_usecase.dart';
import 'package:taxi_app/domain/usecases/client_auth/complete_client_profile_usecase.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/phone_auth/widgets/image_picker_tile.dart';
import 'package:taxi_app/presentation/controllers/auth/complete_profile_controller.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';

class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({
    super.key,
    required this.uid,
    this.initialNombre,
    this.initialApellido,
    this.initialTelefono,
    this.fromOtpFlow = false,
  });

  final String uid;
  final String? initialNombre;
  final String? initialApellido;
  final String? initialTelefono;
  final bool fromOtpFlow;

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  late final TextEditingController _nombreController;
  late final TextEditingController _apellidoController;
  late final TextEditingController _telefonoController;

  bool _hydratedFromData = false;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.initialNombre ?? '');
    _apellidoController = TextEditingController(
      text: widget.initialApellido ?? '',
    );
    _telefonoController = TextEditingController(
      text: _normalizeToTenDigits(widget.initialTelefono),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CompleteProfileController>(
      create: (context) {
        try {
          return CompleteProfileController(
            uid: widget.uid,
            getClientUserUseCase: Provider.of<GetClientUserUseCase>(context, listen: false),
            completeClientProfileUseCase: Provider.of<CompleteClientProfileUseCase>(context, listen: false),
          )..loadInitialData();
        } catch (_) {
          return CompleteProfileController(uid: widget.uid)..loadInitialData();
        }
      },
      child: Consumer<CompleteProfileController>(
        builder: (context, vm, _) {
          _hydrateFieldsFromRemote(vm);

          final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              title: const Text('Completa tu perfil'),
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              elevation: 0,
            ),
            body: SafeArea(
              bottom: false,
              child: vm.loadingInitial
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 140),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Informacion obligatoria',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: AppColores.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Completa tus datos para continuar en la app.',
                                    style: TextStyle(
                                      color: AppColores.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if ((vm.currentUser?.fotoUrl ?? '')
                                          .isNotEmpty &&
                                      vm.selectedImage == null)
                                    Align(
                                      alignment: Alignment.center,
                                      child: CircleAvatar(
                                        radius: 34,
                                        backgroundImage: NetworkImage(
                                          vm.currentUser!.fotoUrl,
                                        ),
                                      ),
                                    ),
                                  if ((vm.currentUser?.fotoUrl ?? '')
                                          .isNotEmpty &&
                                      vm.selectedImage == null)
                                    const SizedBox(height: 12),
                                  ImagePickerTile(
                                    title:
                                        'Foto de perfil (opcional pero recomendada)',
                                    image: vm.selectedImage,
                                    circular: true,
                                    onTap: vm.saving
                                        ? () {}
                                        : vm.pickProfileImage,
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _nombreController,
                                    enabled: !vm.saving,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _apellidoController,
                                    enabled: !vm.saving,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Apellido',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _telefonoController,
                                    enabled: !vm.saving,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.done,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Telefono',
                                      hintText: 'Solo 10 digitos',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  if (vm.errorMessage != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      vm.errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColores.buttonCancel,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            bottomNavigationBar: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: keyboardInset + 12),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: vm.saving
                        ? null
                        : () async {
                            await _submit(context, vm);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: AppColores.textWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: vm.saving
                        ? const SizedBox(
                            height: 10,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Guardar datos',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
        },
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
    final resolvedPhone = _resolvePhoneForSubmit(vm);

    final error = await vm.saveProfile(
      nombre: _nombreController.text,
      apellido: _apellidoController.text,
      telefono: resolvedPhone,
      requireTelefono: true,
    );

    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos guardados correctamente.')),
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeClienteView(authUid: widget.uid)),
      (route) => false,
    );
  }

  String _resolvePhoneForSubmit(CompleteProfileController vm) {
    final fromInput = _normalizeToTenDigits(_telefonoController.text);
    if (fromInput.isNotEmpty) {
      return fromInput;
    }

    final fromUser = _normalizeToTenDigits(vm.currentUser?.telefono);
    if (fromUser.isNotEmpty) {
      return fromUser;
    }

    return _normalizeToTenDigits(widget.initialTelefono);
  }

  String _normalizeToTenDigits(String? input) {
    final digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }
}
