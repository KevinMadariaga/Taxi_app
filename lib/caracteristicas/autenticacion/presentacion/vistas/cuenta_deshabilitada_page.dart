import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Pantalla terminal para un usuario con `usuarios/{uid}.deshabilitado ==
/// true` — cuenta deshabilitada por un administrador desde el panel
/// (`UserDataService.deshabilitarUsuario`). Cierra la sesión al entrar.
///
/// Límite conocido: `deshabilitado` es una restricción 100% client-side —
/// `firestore.rules` solo lo usa para impedir que el propio dueño se lo
/// quite (ver la regla `update` de `usuarios/{uid}`), nunca como condición
/// de `allow` en `solicitudes`, `soporte_chats` ni ninguna otra colección.
/// Un token de Firebase Auth ya emitido sigue siendo válido — nada llama
/// `admin.auth().disableUser()` (requeriría una Cloud Function con Admin
/// SDK, no implementada) — así que esta pantalla bloquea la NAVEGACIÓN de
/// la app, no el acceso real a Firestore mientras el token no expire.
class CuentaDeshabilitadaPage extends StatefulWidget {
  const CuentaDeshabilitadaPage({super.key});

  @override
  State<CuentaDeshabilitadaPage> createState() =>
      _CuentaDeshabilitadaPageState();
}

class _CuentaDeshabilitadaPageState extends State<CuentaDeshabilitadaPage> {
  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.block_rounded,
                  color: AppColores.error,
                  size: 56,
                ),
                const SizedBox(height: 18),
                Text(
                  'Cuenta deshabilitada',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Un administrador deshabilitó esta cuenta. Si crees que es un error, contacta con soporte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.palette.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeView()),
                      (route) => false,
                    );
                  },
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
