import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import '../../../../data/models/viewmodels/registro_cliente_viewmodel.dart';
import '../../../../data/models/registro_cliente_model.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/widgets/floating_loader.dart';
import 'package:image_picker/image_picker.dart';


class RegistroClienteView extends StatefulWidget {
  const RegistroClienteView({super.key});

  @override
  State<RegistroClienteView> createState() => _RegistroClienteViewState();
}

class _RegistroClienteViewState extends State<RegistroClienteView> {
  final _nombreController = TextEditingController();
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
    _telefonoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onRegister(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final vm = Provider.of<RegistroClienteViewModel>(context, listen: false);
    final model = RegistroClienteModel(
      nombre: _nombreController.text.trim(),
      telefono: _telefonoController.text.trim(),
      correo: _emailController.text.trim(),
      password: _passwordController.text,
    );
    try {
      final error = await vm.register(model, _profileImage);
      if (!mounted) return;
      if (error != null) {
        _showDialog(context, 'Error', error);
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
      _showDialog(context, 'Error inesperado', e.toString());
    }
  }

  void _showDialog(BuildContext context, String title, String message) {
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final fontSize = width * 0.045;

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
                          CircleAvatar(
                            radius: width * 0.12,
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!) as ImageProvider
                                : const AssetImage('assets/img/taxi.png'),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.camera_alt),
                              onPressed: () async {
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
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: height * 0.03),

                    TextFormField(
                      controller: _nombreController,
                      style: TextStyle(fontSize: fontSize),
                      decoration: InputDecoration(
                        labelText: 'Nombre Completo',
                        labelStyle: TextStyle(fontSize: fontSize),
                        prefixIcon: const Icon(Icons.person),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Ingrese su nombre completo'
                          : null,
                    ),
                    SizedBox(height: height * 0.02),

                    TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(fontSize: fontSize),
                      decoration: InputDecoration(
                        labelText: 'Número de Teléfono',
                        labelStyle: TextStyle(fontSize: fontSize),
                        prefixIcon: const Icon(Icons.phone),
                        border: const OutlineInputBorder(),
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
                      style: TextStyle(fontSize: fontSize),
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        labelStyle: TextStyle(fontSize: fontSize),
                        prefixIcon: const Icon(Icons.email),
                        border: const OutlineInputBorder(),
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
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
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
                      decoration: InputDecoration(
                        labelText: 'Confirmar Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
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
