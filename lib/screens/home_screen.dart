import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/phone_auth/screens/auth_phone_screen.dart';
import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/presentation/controllers/auth/home_auth_controller.dart';
import 'package:taxi_app/domain/usecases/client_auth/sign_in_google_client_usecase.dart';
import 'package:taxi_app/presentation/screens/auth/complete_profile_page.dart';
import 'package:taxi_app/core/services/services.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, VoidCallback? onLegacyFinish});

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
          _error = 'Credenciales invalidas.';
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

      _showLoginSuccessSnackbar();

      final next = await authService.determineInitialScreen();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => next),
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

  Future<void> _loginWithGoogle(HomeAuthController authVm) async {
    setState(() {
      _error = null;
    });

    final result = await authVm.loginWithGoogle();

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _error = authVm.errorMessage ?? 'Error al iniciar sesión con Google.';
      });
      return;
    }

    _showLoginSuccessSnackbar();

    if (result.destination == AuthFlowDestination.completeProfile) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => CompleteProfilePage(
            uid: result.user.id,
            initialNombre: result.user.nombre,
            initialApellido: result.user.apellido,
            initialTelefono: result.user.telefono,
          ),
        ),
        (route) => false,
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeClienteView(authUid: result.user.id),
      ),
      (route) => false,
    );
  }

  void _showLoginSuccessSnackbar() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: AwesomeSnackbarContent(
          title: 'Acceso confirmado',
          message: 'Sesion iniciada correctamente. Redirigiendo...',
          contentType: ContentType.success,
          color: AppColores.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return ChangeNotifierProvider<HomeAuthController>(
      create: (context) {
        try {
          return HomeAuthController(
            signInGoogleClientUseCase: Provider.of<SignInGoogleClientUseCase>(
              context,
              listen: false,
            ),
          );
        } catch (_) {
          return HomeAuthController();
        }
      },
      child: Consumer<HomeAuthController>(
        builder: (context, authVm, _) {
          final isBusy = _isLoading || authVm.loading;
          final effectiveError = _error ?? authVm.errorMessage;

          return Scaffold(
            backgroundColor: AppColores.background,
            body: Stack(
              children: [
                SafeArea(
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
                          Center(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: size.height * 0.25,
                                  child: Image.asset(
                                    'assets/img/foreground_car.png',
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
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

                          if (effectiveError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              effectiveError,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isBusy
                                  ? null
                                  : () async {
                                      authVm.clearError();
                                      await _login();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textWhite,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: AppColores.textSecondary.withOpacity(
                                    0.35,
                                  ),
                                  thickness: 1,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'o',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColores.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: AppColores.textSecondary.withOpacity(
                                    0.35,
                                  ),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isBusy
                                  ? null
                                  : () {
                                      authVm.clearError();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const AuthPhoneScreen(),
                                        ),
                                      );
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColores.textPrimary,
                                side: const BorderSide(
                                  color: AppColores.buttonPrimary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.phone),
                              label: const Text(
                                'Ingresar con Telefono',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isBusy
                                  ? null
                                  : () async {
                                      await _loginWithGoogle(authVm);
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColores.textPrimary,
                                side: const BorderSide(
                                  color: AppColores.buttonPrimary,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: Image.asset(
                                'assets/img/icon_google.png',
                                width: 20,
                                height: 20,
                              ),
                              label: const Text(
                                'Ingresar con Google',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isBusy)
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppColores.background.withOpacity(0.75),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'Cargando informacion de tu cuenta...',
                              style: TextStyle(
                                color: AppColores.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
