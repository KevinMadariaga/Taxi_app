import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CambiarContrasenaScreen extends StatefulWidget {
  const CambiarContrasenaScreen({Key? key}) : super(key: key);

  @override
  State<CambiarContrasenaScreen> createState() => _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState extends State<CambiarContrasenaScreen> {
  final TextEditingController actualController = TextEditingController();
  final TextEditingController nuevaController = TextEditingController();
  bool _verActual = false;
  bool _verNueva = false;
  bool _botonHabilitado = false;

  @override
  void initState() {
    super.initState();
    actualController.addListener(_actualizarEstadoBoton);
    nuevaController.addListener(_actualizarEstadoBoton);
  }

  void _actualizarEstadoBoton() {
    setState(() {
      _botonHabilitado = actualController.text.isNotEmpty && nuevaController.text.isNotEmpty;
    });
  }

  @override
  void dispose() {
    actualController.dispose();
    nuevaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColores.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColores.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      backgroundColor: AppColores.background,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Cambiar mi contraseña',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: AppColores.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ingresa la contraseña actual y luego la nueva. Esta debe tener entre 8 y 16 caracteres e incluir al menos 2 números, letras o signos.',
              style: TextStyle(fontSize: 15, color: AppColores.textSecondary),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: actualController,
              obscureText: !_verActual,
              decoration: InputDecoration(
                labelText: 'Contraseña actual',
                labelStyle: const TextStyle(fontSize: 22, color: AppColores.textSecondary),
                border: const UnderlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_verActual ? Icons.visibility : Icons.visibility_off, color: AppColores.buttonPrimary),
                  onPressed: () {
                    setState(() {
                      _verActual = !_verActual;
                    });
                  },
                ),
              ),
              cursorColor: AppColores.primary,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: nuevaController,
              obscureText: !_verNueva,
              decoration: InputDecoration(
                labelText: 'Contraseña nueva',
                labelStyle: const TextStyle(fontSize: 22, color: AppColores.textSecondary),
                border: const UnderlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_verNueva ? Icons.visibility : Icons.visibility_off, color: AppColores.buttonPrimary),
                  onPressed: () {
                    setState(() {
                      _verNueva = !_verNueva;
                    });
                  },
                ),
              ),
              cursorColor: AppColores.primary,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                // Acción para recuperar contraseña
              },
              child: const Text(
                'Olvidé mi contraseña o no tengo una cuenta >',
                style: TextStyle(fontSize: 15, color: AppColores.textSecondary),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _botonHabilitado ? () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  final actual = actualController.text.trim();
                  final nueva = nuevaController.text.trim();
                  try {
                    // Reautenticación con la contraseña actual
                    final cred = EmailAuthProvider.credential(
                      email: user.email ?? '',
                      password: actual,
                    );
                    await user.reauthenticateWithCredential(cred);
                    // Actualizar la contraseña
                    await user.updatePassword(nueva);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contraseña actualizada correctamente')),
                      );
                      Navigator.of(context).pop();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString()}')),
                      );
                    }
                  }
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _botonHabilitado ? AppColores.buttonPrimary : AppColores.buttonPrimary,
                  foregroundColor: AppColores.textWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('Confirmar', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
