import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';

import '../controllers/registro_cliente_controller.dart';
import '../widgets/image_picker_tile.dart';

class RegistroClientePhoneScreen extends StatefulWidget {
  const RegistroClientePhoneScreen({
    super.key,
    required this.uid,
    required this.telefono,
  });

  final String uid;
  final String telefono;

  @override
  State<RegistroClientePhoneScreen> createState() =>
      _RegistroClientePhoneScreenState();
}

class _RegistroClientePhoneScreenState
    extends State<RegistroClientePhoneScreen> {
  final TextEditingController _nombreController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RegistroClienteController>(
      create: (_) =>
          RegistroClienteController(uid: widget.uid, telefono: widget.telefono),
      child: Consumer<RegistroClienteController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              title: const Text('Registro de cliente'),
            ),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Completa tu perfil',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColores.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Telefono verificado: ${widget.telefono}',
                              style: const TextStyle(
                                color: AppColores.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _nombreController,
                              enabled: !vm.saving,
                              decoration: const InputDecoration(
                                labelText: 'Nombre',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ImagePickerTile(
                              title: 'Tomar foto de perfil',
                              image: vm.profileImage,
                              circular: true,
                              onTap: () => vm.pickProfileImage(context),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: vm.saving
                                  ? null
                                  : () async {
                                      await _registerClient(context, vm);
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
                                  : const Text('Guardar y continuar'),
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

  Future<void> _registerClient(
    BuildContext context,
    RegistroClienteController vm,
  ) async {
    final error = await vm.registerClient(nombre: _nombreController.text);
    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeClienteView(authUid: widget.uid)),
      (route) => false,
    );
  }
}
