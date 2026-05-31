import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_ingreso_screen.dart';
import 'package:taxi_app/features/phone_auth/controllers/phone_auth_controller.dart';

class LoginConductor extends StatefulWidget {
  const LoginConductor({super.key});

  @override
  State<LoginConductor> createState() => _LoginConductorState();
}

class _LoginConductorState extends State<LoginConductor> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Ingresa correo y contraseña.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = AuthService();
      final usuariosSnapshot = await _buscarUsuarioPorCorreo(email);
      if (usuariosSnapshot == null) {
        setState(() {
          _error = 'No existe una cuenta con ese correo en usuarios.';
        });
        return;
      }

      final userData = usuariosSnapshot.data();
      final role = (userData['rol'] ?? userData['tipoUsuario'] ?? '')
          .toString()
          .toLowerCase();
      if (role != 'cliente' && role != 'conductor' && role != 'administrador') {
        setState(() {
          _error = 'El usuario no tiene un rol valido en usuarios.';
        });
        return;
      }

      final passwordEnUsuarios =
          (userData['passwordLogin'] ?? userData['password'] ?? '')
              .toString()
              .trim();
      if (passwordEnUsuarios.isNotEmpty && passwordEnUsuarios != password) {
        setState(() {
          _error = 'Credenciales inválidas.';
        });
        return;
      }

      final credential = await authService.loginWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential?.user;
      if (user == null) {
        setState(() {
          _error = 'No se pudo obtener la información del usuario.';
        });
        return;
      }

      // Guardar rol detectado en la sesión
      await authService.saveUserSession(
        role: role,
        isLoggedIn: true,
        uid: user.uid,
      );

      if (!mounted) return;

      final next = await authService.determineInitialScreen();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    } on FirebaseAuthException {
      setState(() {
        _error = 'Correo o contraseña incorrectos.';
      });
    } catch (_) {
      setState(() {
        _error = 'Error al iniciar sesión. Verifica tus datos.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _buscarUsuarioPorCorreo(
    String email,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();

    final byCorreo = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('correo', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (byCorreo.docs.isNotEmpty) {
      return byCorreo.docs.first;
    }

    final byEmail = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (byEmail.docs.isNotEmpty) {
      return byEmail.docs.first;
    }

    return null;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Ingreso Conductor'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Image.asset(
                  'assets/img/foreground_car.png',
                  height: 190,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ingresa tus credenciales de conductor',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: AppColores.textWhite,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Iniciar sesión',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      final controller = TextEditingController();
                      final accepted = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Acceso administrador'),
                            content: TextField(
                              controller: controller,
                              obscureText: true,
                              decoration: const InputDecoration(
                                hintText: 'Código admin',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Validar'),
                              ),
                            ],
                          );
                        },
                      );

                      if (accepted != true) return;
                      final code = controller.text.trim();
                      if (code.isEmpty) return;

                      // If the code matches the admin secret, open AdminIngresoScreen.
                      if (code == PhoneAuthController.adminSecret) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminIngresoScreen(),
                          ),
                        );
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código incorrecto')),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColores.textPrimary,
                      side: const BorderSide(color: AppColores.buttonPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Acceso administrador'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
