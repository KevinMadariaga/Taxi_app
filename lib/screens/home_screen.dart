import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/services/auth_service.dart';
import '../services/google_sign_in_service.dart';
import 'register_screen.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
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

      // Detectar tipo de usuario según la base de datos (conductor o cliente)
      final conductorDoc = await FirebaseFirestore.instance
          .collection('conductor')
          .doc(user.uid)
          .get();

      String? role;
      if (conductorDoc.exists) {
        role = 'conductor';
      } else {
        final clienteDoc = await FirebaseFirestore.instance
            .collection('cliente')
            .doc(user.uid)
            .get();

        if (clienteDoc.exists) {
          role = 'cliente';
        }
      }

      if (role == null) {
        await authService.logout();
        setState(() {
          _error = 'Tu cuenta no está registrada como cliente ni como conductor.';
        });
        return;
      }

      // Guardar rol detectado en la sesión
      await authService.saveUserSession(role: role, isLoggedIn: true);

      // Mostrar snackbar de bienvenida
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
            title: '¡Bienvenido!',
            message: 'Has iniciado sesión exitosamente.',
            contentType: ContentType.success,
            color: AppColores.primary,
          ),
        ),
      );

      final next = await authService.determineInitialScreen();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => next),
      );
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


  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userCredential = await GoogleSignInService().signInWithGoogle();
      final user = userCredential?.user;
      if (user == null) {
        setState(() {
          _error = 'No se pudo obtener la información del usuario.';
        });
        return;
      }

      // Detectar tipo de usuario según la base de datos (conductor o cliente)
      final conductorDoc = await FirebaseFirestore.instance
          .collection('conductor')
          .doc(user.uid)
          .get();

      String? role;
      if (conductorDoc.exists) {
        role = 'conductor';
      } else {
        final clienteDoc = await FirebaseFirestore.instance
            .collection('cliente')
            .doc(user.uid)
            .get();

        if (clienteDoc.exists) {
          role = 'cliente';
        }
      }

      if (role == null) {
        await AuthService().logout();
        setState(() {
          _error = 'Tu cuenta no está registrada como cliente ni como conductor.';
        });
        return;
      }

      // Guardar rol detectado en la sesión
      await AuthService().saveUserSession(role: role, isLoggedIn: true);

      // Mostrar snackbar de bienvenida
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          content: AwesomeSnackbarContent(
            title: '¡Bienvenido!',
            message: 'Has iniciado sesión exitosamente.',
            contentType: ContentType.success,
          ),
        ),
      );

      final next = await AuthService().determineInitialScreen();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => next),
      );
    } catch (_) {
      setState(() {
        _error = 'Error al iniciar sesión con Google.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColores.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        height: size.height * 0.25,
                        child: Image.asset(
                          'assets/img/taxi.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_taxi,
                            size: 120,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ingresa para continuar tu viaje',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColores.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Campos de login
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: const Icon(Icons.email),
                    border: const OutlineInputBorder(),
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

                const SizedBox(height: 20),

                // Botón iniciar sesión
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SocialIconButton(
                      asset: 'assets/img/icon_google.png',
                      onTap: _loginWithGoogle,
                    ),
                    const SizedBox(width: 24),
                    _SocialIconButton(
                      asset: 'assets/img/icon_facebook.png',
                      onTap: () {}, // Aquí puedes implementar el login de Facebook
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('¿No tienes cuenta? ', style: TextStyle(fontSize: 14, color: Colors.black54)),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                      child: Text(
                        'Regístrate',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColores.buttonPrimary,
                          fontWeight: FontWeight.bold,
                          
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
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  final String asset;
  final VoidCallback onTap;
  const _SocialIconButton({required this.asset, required this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          border: Border.all(color: AppColores.buttonPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Center(
          child: Image.asset(asset, width: 32, height: 32),
        ),
      ),
    );
  }
}
