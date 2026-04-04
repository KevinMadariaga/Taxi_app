import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import '../../../../data/models/viewmodels/registro_cliente_viewmodel.dart';
import '../../../../data/models/registro_cliente_model.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/widgets/floating_loader.dart';
import 'package:animated_snack_bar/animated_snack_bar.dart';
import 'package:image_picker/image_picker.dart';

class RegistroClienteView extends StatefulWidget {
  const RegistroClienteView({super.key});

  @override
  State<RegistroClienteView> createState() => _RegistroClienteViewState();
}

class _RegistroClienteViewState extends State<RegistroClienteView> {
  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onRegister(BuildContext context) async {
    if (_nombreController.text.trim().isEmpty ||
        _apellidoController.text.trim().isEmpty ||
        _telefonoController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      AnimatedSnackBar.material(
        'Todos los campos son obligatorios',
        type: AnimatedSnackBarType.error,
        duration: const Duration(seconds: 2),
      ).show(context);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Validar que teléfono solo tenga números
    if (!RegExp(r'^\d{10,}$').hasMatch(_telefonoController.text.trim())) {
      AnimatedSnackBar.material(
        'El número de teléfono solo debe contener números y tener al menos 10 dígitos',
        type: AnimatedSnackBarType.error,
        duration: const Duration(seconds: 2),
      ).show(context);
      return;
    }

    // Validar que el correo no esté registrado
    final firestore = Provider.of<RegistroClienteViewModel>(
      context,
      listen: false,
    );
    final email = _emailController.text.trim();
    final emailExists = await FirebaseFirestore.instance
        .collection('cliente')
        .where('correo', isEqualTo: email)
        .get();
    if (emailExists.docs.isNotEmpty) {
      AnimatedSnackBar.material(
        'El correo ya está registrado',
        type: AnimatedSnackBarType.error,
        duration: const Duration(seconds: 2),
      ).show(context);
      return;
    }

    final model = RegistroClienteModel(
      nombre: _nombreController.text.trim(),
      apellido: _apellidoController.text.trim(),
      telefono: _telefonoController.text.trim(),
      correo: _emailController.text.trim(),
      password: _passwordController.text,
    );
    try {
      final error = await firestore.register(model, _profileImage);
      if (!mounted) return;
      if (error != null) {
        AnimatedSnackBar.material(
          error,
          type: AnimatedSnackBarType.error,
          duration: const Duration(seconds: 2),
        ).show(context);
        return;
      }

      if (!mounted) return;
      // Mostrar loader flotante: visible 1s, luego fade 400ms
      await showFloatingLoader(
        context,
        visibleDuration: const Duration(seconds: 1),
        fadeDuration: const Duration(milliseconds: 400),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const InicioClienteView()),
      );
    } catch (e) {
      if (!mounted) return;
      AnimatedSnackBar.material(
        'Error inesperado: ${e.toString()}',
        type: AnimatedSnackBarType.error,
        duration: const Duration(seconds: 2),
      ).show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final fontSize = width * 0.045;
    final inputDecoration = InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColores.buttonPrimary, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(
        vertical: width * 0.018,
        horizontal: width * 0.03,
      ),
      fillColor: Colors.white,
      filled: true,
    );

    return ChangeNotifierProvider(
      create: (_) => RegistroClienteViewModel(),
      child: Consumer<RegistroClienteViewModel>(
        builder: (context, vm, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Registro de Cliente'),
            backgroundColor: Colores.amarillo,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          SizedBox(
                            width: width * 0.24,
                            height: width * 0.24,
                            child: ClipOval(
                              child: _profileImage != null
                                  ? Image.file(
                                      _profileImage!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: Colors.grey.shade200,
                                      child: Center(
                                        child: Icon(
                                          Icons.person,
                                          size: width * 0.13,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: InkWell(
                              onTap: () async {
                                final picked = await _picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 75,
                                );
                                if (picked != null) {
                                  setState(() {
                                    _profileImage = File(picked.path);
                                  });
                                }
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColores.buttonPrimary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: height * 0.03),

                    TextFormField(
                      controller: _nombreController,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Nombre',
                        prefixIcon: const Icon(Icons.person),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Ingrese su nombre'
                          : null,
                    ),
                    SizedBox(height: height * 0.02),
                    TextFormField(
                      controller: _apellidoController,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Apellido',
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Ingrese su apellido'
                          : null,
                    ),
                    SizedBox(height: height * 0.02),

                    TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Número de Teléfono',
                        prefixIcon: const Icon(Icons.phone),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese su número de teléfono';
                        }
                        if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                          return 'Número inválido (10 dígitos)';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: height * 0.02),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Correo Electrónico',
                        prefixIcon: const Icon(Icons.email),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese su correo';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'Correo inválido';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: height * 0.02),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          }),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese su contraseña';
                        }
                        if (value.length < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      style: TextStyle(
                        fontSize: fontSize,
                        color: AppColores.textPrimary,
                      ),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Confirmar Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() {
                            _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible;
                          }),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirme su contraseña';
                        }
                        if (value != _passwordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: height * 0.04),
                    vm.loading
                        ? const Center(child: CircularProgressIndicator())
                        : CustomButton(
                            text: 'Registrar',
                            onPressed: () => _onRegister(context),
                            width: width * 0.3,
                            height: 50,
                            fontSize: fontSize,
                          ),

                    // Divider y registro con Gmail
                    SizedBox(height: height * 0.03),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: Colors.grey, thickness: 1),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            'O regístrate con',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: fontSize,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: Colors.grey, thickness: 1),
                        ),
                      ],
                    ),
                    SizedBox(height: height * 0.02),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () {
                            // Aquí deberías llamar al método de registro con Google
                            // Por ejemplo: vm.registerWithGoogle(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/img/icon_google.png',
                                  width: 28,
                                  height: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        InkWell(
                          onTap: () {
                            // Aquí deberías llamar al método de registro con Apple
                            // Por ejemplo: vm.registerWithApple(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.08),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.apple,
                                  size: 28,
                                  color: Colors.black,
                                ),
                              ],
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
        ),
      ),
    );
  }
}
