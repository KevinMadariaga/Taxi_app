import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
// import 'package:taxi_app/features/phone_auth/screens/auth_phone_screen.dart';
import 'package:taxi_app/domain/models/auth_flow_result.dart';
import 'package:taxi_app/presentation/controllers/auth/home_auth_controller.dart';
import 'package:taxi_app/domain/usecases/client_auth/sign_in_google_client_usecase.dart';
import 'package:taxi_app/presentation/screens/auth/complete_profile_page.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:taxi_app/screens/login_conductor_screen.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, VoidCallback? onLegacyFinish});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    super.dispose();
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
                          if (effectiveError != null) ...[
                            Text(
                              effectiveError,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Inicio por teléfono deshabilitado por petición del usuario.
                          // SizedBox(
                          //   width: double.infinity,
                          //   child: ElevatedButton.icon(
                          //     onPressed: isBusy
                          //         ? null
                          //         : () {
                          //             authVm.clearError();
                          //             Navigator.push(
                          //               context,
                          //               MaterialPageRoute(
                          //                 builder: (context) =>
                          //                     const AuthPhoneScreen(),
                          //               ),
                          //             );
                          //           },
                          //     style: ElevatedButton.styleFrom(
                          //       backgroundColor: AppColores.buttonPrimary,
                          //       foregroundColor: AppColores.textWhite,
                          //       padding: const EdgeInsets.symmetric(
                          //         vertical: 14,
                          //       ),
                          //       shape: RoundedRectangleBorder(
                          //         borderRadius: BorderRadius.circular(8),
                          //       ),
                          //     ),
                          //     icon: const Icon(Icons.phone),
                          //     label: const Text(
                          //       'Ingresa tu número',
                          //       style: TextStyle(
                          //         fontSize: 16,
                          //         fontWeight: FontWeight.w600,
                          //       ),
                          //     ),
                          //   ),
                          // ),
                          const SizedBox(height: 20),
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
                                'Ingresar con Gmail',
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
                                      authVm.clearError();
                                      final result = await authVm
                                          .loginWithApple();
                                      if (result == null) {
                                        setState(() {
                                          _error =
                                              authVm.errorMessage ??
                                              'Apple Sign-in no disponible.';
                                        });
                                      } else {
                                        _showLoginSuccessSnackbar();
                                        if (result.destination ==
                                            AuthFlowDestination
                                                .completeProfile) {
                                          Navigator.of(
                                            context,
                                          ).pushAndRemoveUntil(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CompleteProfilePage(
                                                    uid: result.user.id,
                                                    initialNombre:
                                                        result.user.nombre,
                                                    initialApellido:
                                                        result.user.apellido,
                                                    initialTelefono:
                                                        result.user.telefono,
                                                  ),
                                            ),
                                            (route) => false,
                                          );
                                          return;
                                        }
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (_) => HomeClienteView(
                                              authUid: result.user.id,
                                            ),
                                          ),
                                          (route) => false,
                                        );
                                      }
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
                              icon: const Icon(Icons.apple, size: 20),
                              label: const Text(
                                'Ingresar con Apple',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const LoginConductor(),
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
                              icon: const Icon(Icons.directions_car),
                              label: const Text(
                                'Ingresar como conductor',
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
                      color: AppColores.background.withValues(alpha: 0.75),
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
