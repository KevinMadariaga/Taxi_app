import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../controllers/registro_conductor_controller.dart';
import '../widgets/image_picker_tile.dart';

class RegistroConductorScreen extends StatefulWidget {
  const RegistroConductorScreen({super.key, required this.adminId});

  final String adminId;

  @override
  State<RegistroConductorScreen> createState() =>
      _RegistroConductorScreenState();
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conductor registrado correctamente.')),
    );

    final correo = vm.generatedEmail ?? '';
    final password = vm.generatedPassword ?? '';
    if (correo.isNotEmpty && password.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: AppColores.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: AppColores.textPrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Credenciales generadas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColores.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColores.textPrimary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Comparte esta informacion con el conductor y guardala en un lugar seguro.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColores.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColores.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          size: 20,
                          color: AppColores.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Correo',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColores.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                correo,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar correo',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: correo),
                            );
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Correo copiado')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColores.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                          color: AppColores.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Contrasena',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColores.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                password,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar contrasena',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: password),
                            );
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Contrasena copiada'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 19),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Entendido'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColores.buttonPrimary,
                      foregroundColor: AppColores.textWhite,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Navigator.of(context).pop(true);
  }
}
