import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/registro_conductor_viewmodel.dart';
import 'dart:io';
import 'package:taxi_app/widgets/sucess_overlay.dart';

class RegistroConductorView extends StatefulWidget {
  const RegistroConductorView({super.key});

  @override
  State<RegistroConductorView> createState() => _RegistroConductorViewState();
}

class _RegistroConductorViewState extends State<RegistroConductorView> {
  late final RegistroConductorViewModel vm;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    vm = RegistroConductorViewModel();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  void _showDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Usamos el helper reutilizable `SuccessOverlay.show(...)` en su lugar.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Conductor'),
        backgroundColor: AppColores.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: vm.formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Perfil: avatar seleccionable
                ValueListenableBuilder<XFile?>(
                  valueListenable: vm.selectedImage,
                  builder: (context, img, _) {
                    return GestureDetector(
                      onTap: () async {
                        await vm.pickImage();
                        setState(() {});
                      },
                      child: CircleAvatar(
                        radius: 65,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: img != null ? FileImage(File(img.path)) : null,
                        child: img == null
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.camera_alt, size: 32, color: Colors.black54),
                                  SizedBox(height: 6),
                                  Text('Agregar foto', style: TextStyle(fontSize: 12)),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: vm.nombreController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Ingrese su nombre completo'
                      : null,
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: vm.placaController,
                  decoration: const InputDecoration(
                    labelText: 'Numero de Placa',
                    prefixIcon: Icon(Icons.perm_identity),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: vm.telefonoController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Número de Teléfono',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Ingrese su número de teléfono';
                    }
                    if (v.length != 10) {
                      return 'Número inválido (10 dígitos)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: vm.emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Ingrese su correo';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
                      return 'Correo inválido';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: vm.passwordController,
                  obscureText: !_isPasswordVisible,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (vm.passwordController.text.isNotEmpty)
                          Icon(
                            vm.passwordController.text.length >= 6
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: vm.passwordController.text.length >= 6
                                ? Colors.green
                                : Colors.red,
                          ),
                        IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                        ),
                      ],
                    ),
                    border: const OutlineInputBorder(),
                    errorText:
                        vm.passwordController.text.isNotEmpty &&
                            vm.passwordController.text.length < 6
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                ),

                const SizedBox(height: 12),
                TextFormField(
                  controller: vm.confirmPasswordController,
                  obscureText: !_isPasswordVisible,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Confirmar Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: vm.confirmPasswordController.text.isNotEmpty
                        ? Icon(
                            vm.confirmPasswordController.text.length >= 6 &&
                                    vm.confirmPasswordController.text ==
                                        vm.passwordController.text
                                ? Icons.check_circle
                                : Icons.cancel,
                            color:
                                vm.confirmPasswordController.text.length >= 6 &&
                                    vm.confirmPasswordController.text ==
                                        vm.passwordController.text
                                ? Colors.green
                                : Colors.red,
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    errorText:
                        vm.confirmPasswordController.text.isNotEmpty &&
                            vm.confirmPasswordController.text.length < 6
                        ? 'Mínimo 6 caracteres'
                        : vm.confirmPasswordController.text !=
                              vm.passwordController.text
                        ? 'Las contraseñas no coinciden'
                        : null,
                  ),
                ),

                const SizedBox(height: 18),
                ValueListenableBuilder<bool>(
                  valueListenable: vm.isLoading,
                  builder: (context, loading, _) {
                    return CustomButton(
                      text: loading ? 'Registrando...' : 'Registrar',
                      onPressed: loading
                            ? null
                            : () async {
                                final BuildContext ctx = context;

                                final ok = await vm.register();

                                if (ok) {
                                  if (!mounted) return; // guard State.context uses

                                  if (!ctx.mounted) return; // guard captured BuildContext

                                  // Mostrar overlay dinámico de registro completo (reusable)
                                  await SuccessOverlay.show(
                                    ctx,
                                    message: 'Registro completo',
                                  );

                                  if (!ctx.mounted) return;

                                  // Navegar inmediatamente después de la animación
                                  Navigator.pushReplacement(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (c) => const HomeConductorMapView(),
                                    ),
                                  );
                                } else if (vm.error.value != null) {
                                  if (!mounted) return;
                                  _showDialog('Error', vm.error.value!);
                                }
                              },
                      // Remove fixed width so button becomes responsive
                      height: 50,
                      fontSize: 16,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
