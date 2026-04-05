import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/registro_administrador_controller.dart';
import '../widgets/image_picker_tile.dart';
import 'panel_administrador_screen.dart';

class RegistroAdministradorScreen extends StatefulWidget {
  const RegistroAdministradorScreen({
    super.key,
    required this.uid,
    required this.telefono,
  });

  final String uid;
  final String telefono;

  @override
  State<RegistroAdministradorScreen> createState() =>
      _RegistroAdministradorScreenState();
}

class _RegistroAdministradorScreenState
    extends State<RegistroAdministradorScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _gremioController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _gremioController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _telefonoController.text = widget.telefono;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RegistroAdministradorController>(
      create: (_) => RegistroAdministradorController(
        uid: widget.uid,
        telefono: widget.telefono,
      ),
      child: Consumer<RegistroAdministradorController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              title: const Text('Registro de administrador'),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Text(
                                'Completa tu perfil de administrador',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ImagePickerTile(
                              title: 'Seleccionar foto de perfil',
                              image: vm.profileImage,
                              circular: true,
                              onTap: vm.pickProfileImage,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _gremioController,
                              decoration: const InputDecoration(
                                labelText: 'Gremio o asociacion',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Telefono',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: vm.saving
                                  ? null
                                  : () async {
                                      await _registerAdmin(context, vm);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textWhite,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: vm.saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Registrar administrador'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _registerAdmin(
    BuildContext context,
    RegistroAdministradorController vm,
  ) async {
    final error = await vm.registerAdmin(
      nombre: _nombreController.text,
      gremio: _gremioController.text,
      telefonoParam: _telefonoController.text,
    );

    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      // Re-open the registration screen so the user can correct data
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RegistroAdministradorScreen(
            uid: widget.uid,
            telefono: widget.telefono,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => PanelAdministradorScreen(adminId: widget.uid),
      ),
      (route) => false,
    );
  }
}
