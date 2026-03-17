import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/registro_conductor_controller.dart';
import '../widgets/image_picker_tile.dart';

class RegistroConductorScreen extends StatefulWidget {
  const RegistroConductorScreen({super.key, required this.adminId});

  final String adminId;

  @override
  State<RegistroConductorScreen> createState() => _RegistroConductorScreenState();
}

class _RegistroConductorScreenState extends State<RegistroConductorScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _placaController = TextEditingController();

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _placaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RegistroConductorController>(
      create: (_) => RegistroConductorController(adminId: widget.adminId),
      child: Consumer<RegistroConductorController>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: AppColores.background,
            appBar: AppBar(
              title: const Text('Registrar conductor'),
              backgroundColor: AppColores.background,
              foregroundColor: AppColores.textPrimary,
              elevation: 0,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _nombreController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del conductor',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Telefono',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _placaController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Placa del vehiculo',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ImagePickerTile(
                              title: 'Foto del conductor',
                              image: vm.fotoConductor,
                              circular: true,
                              onTap: vm.pickFotoConductor,
                            ),
                            const SizedBox(height: 10),
                            ImagePickerTile(
                              title: 'Foto del vehiculo',
                              image: vm.fotoVehiculo,
                              onTap: vm.pickFotoVehiculo,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: vm.saving
                                  ? null
                                  : () async {
                                      await _saveDriver(context, vm);
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Guardar conductor'),
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

  Future<void> _saveDriver(
    BuildContext context,
    RegistroConductorController vm,
  ) async {
    final error = await vm.registrarConductor(
      nombre: _nombreController.text,
      telefono: _telefonoController.text,
      placa: _placaController.text,
    );

    if (!context.mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conductor registrado correctamente.')),
    );
    Navigator.of(context).pop(true);
  }
}
