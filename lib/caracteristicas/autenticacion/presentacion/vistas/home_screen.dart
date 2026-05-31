import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/utils/transicion_pagina.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/modelos/auth_flow_result.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/controladores/home_auth_controller.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/complete_profile_page.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/login_conductor_screen.dart';

/// Pantalla de inicio de sesión del cliente.
/// Diseño pulido: hero de marca + accesos sociales (Google / Apple).
/// La carga se muestra de forma sutil dentro del propio botón (sin overlay
/// que bloquee la pantalla) y la navegación es directa, sin snackbars.
class HomeView extends StatefulWidget {
  const HomeView({super.key, VoidCallback? onLegacyFinish});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String? _error;
  // Proveedor que está autenticando ahora mismo ('google' | 'apple' | null).
  String? _proveedorCargando;

  Future<void> _loginWithGoogle(HomeAuthController authVm) async {
    setState(() {
      _error = null;
      _proveedorCargando = 'google';
    });
    authVm.clearError();

    final result = await authVm.loginWithGoogle();
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _error = authVm.errorMessage ?? 'No se pudo iniciar sesión con Google.';
        _proveedorCargando = null;
      });
      return;
    }
    _navegarTrasLogin(result);
  }

  Future<void> _loginWithApple(HomeAuthController authVm) async {
    setState(() {
      _error = null;
      _proveedorCargando = 'apple';
    });
    authVm.clearError();

    final result = await authVm.loginWithApple();
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _error = authVm.errorMessage ?? 'Apple Sign-in no disponible.';
        _proveedorCargando = null;
      });
      return;
    }
    _navegarTrasLogin(result);
  }

  /// Navegación directa tras un login exitoso (sin diálogos ni snackbars).
  void _navegarTrasLogin(AuthFlowResult result) {
    if (!mounted) return;

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
      transicionInicioCliente(HomeClienteView(authUid: result.user.id)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
          final bool isBusy = _proveedorCargando != null || authVm.loading;
          final String? effectiveError = _error ?? authVm.errorMessage;

          return Scaffold(
            backgroundColor: AppColores.background,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double alturaViewport = constraints.maxHeight;
                  final double espacioSuperior =
                      (alturaViewport * 0.08).clamp(12.0, 72.0);
                  final double espacioEntreHeroYAcciones =
                      (alturaViewport * 0.12).clamp(16.0, 96.0);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                        maxWidth: 460,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: espacioSuperior),
                          _Hero(),
                          SizedBox(height: espacioEntreHeroYAcciones),

                          if (effectiveError != null) ...[
                            _ErrorBanner(message: effectiveError),
                            const SizedBox(height: 16),
                          ],

                          // ── Google ─────────────────────────────────────
                          _SocialButton(
                            label: 'Continuar con Google',
                            loading: _proveedorCargando == 'google',
                            enabled: !isBusy,
                            filled: false,
                            leading: Image.asset(
                              'assets/img/icon_google.png',
                              width: 22,
                              height: 22,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.g_mobiledata_rounded,
                                size: 26,
                              ),
                            ),
                            onTap: () => _loginWithGoogle(authVm),
                          ),
                          const SizedBox(height: 12),

                          // ── Apple ──────────────────────────────────────
                          _SocialButton(
                            label: 'Continuar con Apple',
                            loading: _proveedorCargando == 'apple',
                            enabled: !isBusy,
                            filled: true,
                            leading: const Icon(
                              Icons.apple,
                              size: 24,
                              color: Colors.white,
                            ),
                            onTap: () => _loginWithApple(authVm),
                          ),

                          const SizedBox(height: 22),

                          // ── Acceso conductor (sutil) ───────────────────
                          TextButton(
                            onPressed: isBusy
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginConductor(),
                                    ),
                                  ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColores.textSecondary,
                            ),
                            child: const Text.rich(
                              TextSpan(
                                text: '¿Eres conductor?  ',
                                children: [
                                  TextSpan(
                                    text: 'Ingresa aquí',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColores.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),
                          Text(
                            'Al continuar aceptas nuestros Términos y la\n'
                            'Política de privacidad.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColores.textSecondary.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero de marca
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Column(
      children: [
        SizedBox(
          height: (h * 0.22).clamp(140.0, 220.0),
          child: Image.asset(
            'assets/img/foreground_car.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Icon(
              Icons.local_taxi_rounded,
              size: 110,
              color: AppColores.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Taxi Ya',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: AppColores.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu viaje, a un toque de distancia',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColores.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón social reutilizable (con carga inline)
// ─────────────────────────────────────────────────────────────────────────────

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.leading,
    required this.onTap,
    required this.loading,
    required this.enabled,
    required this.filled,
  });

  final String label;
  final Widget leading;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color bg = filled ? Colors.black : AppColores.surface;
    final Color fg = filled ? Colors.white : AppColores.textPrimary;

    return SizedBox(
      height: 54,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        elevation: filled ? 0 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled
                  ? null
                  : Border.all(color: AppColores.grey300, width: 1.4),
            ),
            child: Center(
              child: loading
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(opacity: enabled ? 1 : 0.5, child: leading),
                        const SizedBox(width: 12),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: fg.withValues(alpha: enabled ? 1 : 0.5),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner de error (no bloqueante)
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final bool offline = message.toLowerCase().contains('conex');
    final Color accent = offline ? AppColores.warning : AppColores.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
            size: 20,
            color: accent,
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
