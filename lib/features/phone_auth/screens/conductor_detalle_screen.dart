import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';

import '../models/driver_model.dart';
import '../services/storage_service.dart';
import '../services/user_data_service.dart';

class ConductorDetalleScreen extends StatelessWidget {
  const ConductorDetalleScreen({super.key, required this.conductorId});

  final String conductorId;

  Future<void> _actualizarEstado(
    BuildContext context,
    UserDataService userDataService,
    DriverModel conductor,
    bool activo,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await userDataService.actualizarEstadoConductor(
        conductorId: conductor.idConductor,
        activo: activo,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activo
                ? 'Conductor marcado como activo.'
                : 'Conductor marcado como inactivo.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'No se pudo actualizar estado.'),
        ),
      );
    }
  }

  Future<void> _editarNombreYFoto(
    BuildContext context,
    UserDataService userDataService,
    DriverModel conductor,
  ) async {
    final nombreController = TextEditingController(text: conductor.nombre);
    final telefonoController = TextEditingController(text: conductor.telefono);
    final placaController = TextEditingController(text: conductor.placa);
    final picker = ImagePicker();
    final storageService = StorageService();
    XFile? nuevaFoto;
    XFile? nuevaFotoVehiculo;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              title: Row(
                children: const [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColores.primary,
                    child: Icon(
                      Icons.edit_outlined,
                      color: AppColores.textPrimary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Editar perfil del conductor',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Actualiza la informacion principal y las fotos.',
                        style: TextStyle(
                          color: AppColores.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nombreController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: telefonoController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Telefono',
                          hintText: 'Solo numeros',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: placaController,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Placa',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 80,
                            maxWidth: 1400,
                          );
                          if (picked == null) return;
                          setLocal(() => nuevaFoto = picked);
                        },
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(
                          nuevaFoto == null
                              ? 'Cambiar foto del conductor'
                              : 'Foto del conductor seleccionada',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 80,
                            maxWidth: 1600,
                          );
                          if (picked == null) return;
                          setLocal(() => nuevaFotoVehiculo = picked);
                        },
                        icon: const Icon(Icons.directions_car_outlined),
                        label: Text(
                          nuevaFotoVehiculo == null
                              ? 'Cambiar foto del vehiculo'
                              : 'Foto del vehiculo seleccionada',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true || !context.mounted) return;
    final nombre = nombreController.text.trim();
    final telefono = telefonoController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final placa = placaController.text.trim().toUpperCase();

    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre no puede estar vacio.')),
      );
      return;
    }
    if (telefono.length < 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un telefono valido.')),
      );
      return;
    }
    if (placa.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una placa valida.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String? fotoUrl;
      String? fotoVehiculoUrl;
      if (nuevaFoto != null) {
        fotoUrl = await storageService.uploadImage(
          file: File(nuevaFoto!.path),
          path: 'conductores/${conductor.idConductor}/foto_conductor.webp',
        );
      }

      if (nuevaFotoVehiculo != null) {
        fotoVehiculoUrl = await storageService.uploadImage(
          file: File(nuevaFotoVehiculo!.path),
          path: 'conductores/${conductor.idConductor}/foto_vehiculo.webp',
        );
      }

      await userDataService.actualizarPerfilConductor(
        conductorId: conductor.idConductor,
        nombre: nombre,
        telefono: telefono,
        placa: placa,
        fotoConductor: fotoUrl,
        fotoVehiculo: fotoVehiculoUrl,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil del conductor actualizado.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'No se pudo actualizar perfil.'),
        ),
      );
    }
  }

  Future<void> _editarCredenciales(
    BuildContext context,
    UserDataService userDataService,
    DriverModel conductor,
  ) async {
    final emailController = TextEditingController(text: conductor.correo);
    final passController = TextEditingController(text: conductor.passwordLogin);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          title: Row(
            children: const [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColores.primary,
                child: Icon(
                  Icons.vpn_key_outlined,
                  color: AppColores.textPrimary,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Modificar credenciales',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Actualiza el correo y la contraseña de acceso del conductor.',
                    style: TextStyle(
                      color: AppColores.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirm != true || !context.mounted) return;

    final correo = emailController.text.trim();
    final password = passController.text.trim();
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(correo)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Correo inválido.')));
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña debe tener al menos 6 caracteres.'),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await userDataService.actualizarCredencialesConductor(
        conductorId: conductor.idConductor,
        correo: correo,
        password: password,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Credenciales actualizadas para ${result.email}.'),
        ),
      );

      if (result.conductorId != conductor.idConductor) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ConductorDetalleScreen(conductorId: result.conductorId),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty
                ? msg
                : 'No se pudieron actualizar las credenciales.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userDataService = UserDataService();

    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Detalle de conductor'),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<DriverModel?>(
          stream: userDataService.streamConductor(conductorId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Error cargando conductor: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final conductor = snapshot.data;
            if (conductor == null) {
              return const Center(child: Text('Conductor no encontrado.'));
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CircleAvatar(
                  radius: 72,
                  backgroundColor: AppColores.primary,
                  backgroundImage: conductor.fotoConductor.isNotEmpty
                      ? NetworkImage(conductor.fotoConductor)
                      : null,
                  child: conductor.fotoConductor.isEmpty
                      ? const Icon(Icons.person, size: 52)
                      : null,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    conductor.nombre,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _DetailRow(label: 'Telefono', value: conductor.telefono),
                _DetailRow(label: 'Placa', value: conductor.placa),
                _DetailRow(label: 'Estado', value: conductor.estado),
                const SizedBox(height: 2),
                SwitchListTile.adaptive(
                  value: conductor.estado.toLowerCase() == 'activo',
                  onChanged: (value) => _actualizarEstado(
                    context,
                    userDataService,
                    conductor,
                    value,
                  ),
                  title: const Text('Conductor activo'),
                  subtitle: Text(
                    conductor.estado.toLowerCase() == 'activo'
                        ? 'Disponible para iniciar sesion'
                        : 'Bloqueado para iniciar sesion',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Correo',
                  value: conductor.correo.isNotEmpty
                      ? conductor.correo
                      : 'No configurado',
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () =>
                      _editarNombreYFoto(context, userDataService, conductor),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar datos y fotos'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () =>
                      _editarCredenciales(context, userDataService, conductor),
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Modificar credenciales'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Foto del vehiculo',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 220,
                      height: 120,
                      child: conductor.fotoVehiculo.isNotEmpty
                          ? Image.network(
                              conductor.fotoVehiculo,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColores.grey100,
                              child: const Icon(Icons.directions_car, size: 42),
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColores.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
