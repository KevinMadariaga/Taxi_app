import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/caracteristicas/autenticacion/datos/repositorios/client_auth_repository_impl.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_google_client_usecase.dart';
import 'package:taxi_app/caracteristicas/autenticacion/dominio/casos_uso/sign_in_apple_client_usecase.dart';
import 'registro_administrador_screen.dart';
import 'package:taxi_app/core/services/auth_service.dart';
import '../services/user_data_service.dart';
import 'panel_administrador_screen.dart';

class AdminIngresoScreen extends StatefulWidget {
  const AdminIngresoScreen({super.key});

  @override
  State<AdminIngresoScreen> createState() => _AdminIngresoScreenState();
}

class _AdminIngresoScreenState extends State<AdminIngresoScreen> {
  bool _loading = false;

  final _googleUseCase = SignInGoogleClientUseCase(ClientAuthRepositoryImpl());
  final _appleUseCase = SignInAppleClientUseCase(ClientAuthRepositoryImpl());

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final result = await _googleUseCase();
      final uid = result.user.id;
      final telefono = result.user.telefono;

      // Guardar sesión como administrador
      try {
        await AuthService().saveUserSession(
          role: 'administrador',
          isLoggedIn: true,
          uid: uid,
        );
      } catch (_) {}

      if (!mounted) return;

      try {
        final userDataService = UserDataService();
        final completo = await userDataService.administradorRegistradoCompleto(
          uid,
        );
        if (completo) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => PanelAdministradorScreen(adminId: uid),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  RegistroAdministradorScreen(uid: uid, telefono: telefono),
            ),
          );
        }
      } catch (_) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RegistroAdministradorScreen(uid: uid, telefono: telefono),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _loading = true);
    try {
      final result = await _appleUseCase();
      final uid = result.user.id;
      final telefono = result.user.telefono;

      // Guardar sesión como administrador
      try {
        await AuthService().saveUserSession(
          role: 'administrador',
          isLoggedIn: true,
          uid: uid,
        );
      } catch (_) {}

      if (!mounted) return;

      try {
        final userDataService = UserDataService();
        final completo = await userDataService.administradorRegistradoCompleto(
          uid,
        );
        if (completo) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => PanelAdministradorScreen(adminId: uid),
            ),
            (route) => false,
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  RegistroAdministradorScreen(uid: uid, telefono: telefono),
            ),
          );
        }
      } catch (_) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                RegistroAdministradorScreen(uid: uid, telefono: telefono),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Ingreso administrador'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Ingreso administrador',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Selecciona un método para ingresar como administrador:',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('Ingresar con Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColores.buttonPrimary,
                          foregroundColor: AppColores.textWhite,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _signInWithApple,
                        icon: const Icon(Icons.apple),
                        label: const Text('Ingresar con Apple'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColores.textPrimary,
                          foregroundColor: AppColores.textWhite,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      if (_loading) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
