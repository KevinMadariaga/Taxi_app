import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/core/services/services.dart';

import '../models/admin_model.dart';
import '../services/storage_service.dart';
import '../services/user_data_service.dart';

class AdminDetalleScreen extends StatefulWidget {
  const AdminDetalleScreen({super.key, required this.admin});

  final AdminModel admin;

  @override
  State<AdminDetalleScreen> createState() => _AdminDetalleScreenState();
}

class _AdminDetalleScreenState extends State<AdminDetalleScreen> {
  final UserDataService _userDataService = UserDataService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _busy = false;

  String _telefonoSinPais(String telefonoRaw) {
    final digits = telefonoRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('57') && digits.length > 10) {
      return digits.substring(2);
    }
    return digits.isNotEmpty ? digits : telefonoRaw;
  }

  Future<void> _updateAdmin(
    AdminModel admin, {
    String? nombre,
    String? telefono,
    String? foto,
    String? gremioFoto,
    String successMessage = 'Informacion actualizada.',
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _userDataService.actualizarPerfilAdministrador(
        adminId: admin.uid,
        nombre: nombre,
        telefono: telefono,
        foto: foto,
        gremioFoto: gremioFoto,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'No se pudo actualizar.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editarNombre(AdminModel admin) async {
    final controller = TextEditingController(text: admin.nombre);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar nombre'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (value == null || value.isEmpty || value == admin.nombre.trim()) return;
    await _updateAdmin(
      admin,
      nombre: value,
      successMessage: 'Nombre actualizado.',
    );
  }

  Future<void> _editarTelefono(AdminModel admin) async {
    final controller = TextEditingController(
      text: _telefonoSinPais(admin.telefono),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Editar telefono'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Telefono',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (value == null || value.isEmpty) return;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un telefono valido.')),
      );
      return;
    }
    await _updateAdmin(
      admin,
      telefono: digits,
      successMessage: 'Telefono actualizado.',
    );
  }

  Future<void> _editarFotoPerfil(AdminModel admin) async {
    if (_busy) return;
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1400,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final fotoUrl = await _storageService.uploadImage(
        file: File(picked.path),
        path: 'administradores/${admin.uid}/foto_perfil.webp',
      );
      await _userDataService.actualizarPerfilAdministrador(
        adminId: admin.uid,
        foto: fotoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty ? msg : 'No se pudo actualizar la foto.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editarLogoGremio(AdminModel admin) async {
    if (_busy) return;
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1000,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      final fotoUrl = await _storageService.uploadImage(
        file: File(picked.path),
        path: 'administradores/${admin.uid}/foto_gremio.webp',
      );
      await _userDataService.actualizarPerfilAdministrador(
        adminId: admin.uid,
        gremioFoto: fotoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo de gremio actualizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty ? msg : 'No se pudo actualizar el logo.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cerrarSesion() async {
    if (_busy) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cerrar sesion'),
          content: const Text('¿Quieres cerrar sesion?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _eliminarAdministrador(AdminModel admin) async {
    if (_busy) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Eliminar administrador'),
          content: const Text(
            'Esta accion eliminara tu cuenta de administrador. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No hay sesion activa para eliminar.');
      }

      await user.delete();
      await _userDataService.eliminarAdministradorData(admin.uid);
      await AuthService().logout();

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Por seguridad, inicia sesion de nuevo para poder eliminar la cuenta.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'No se pudo eliminar la cuenta.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.isNotEmpty ? msg : 'No se pudo eliminar la cuenta.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Detalle de administrador'),
        backgroundColor: AppColores.background,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<AdminModel?>(
        stream: _userDataService.streamAdministrador(widget.admin.uid),
        initialData: widget.admin,
        builder: (context, snapshot) {
          final admin = snapshot.data;
          if (admin == null) {
            return const Center(child: Text('Administrador no encontrado.'));
          }

          final hasPhoto = admin.foto.isNotEmpty;
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                      children: [
                        Center(
                          child: InkWell(
                            onTap: _busy
                                ? null
                                : () => _editarFotoPerfil(admin),
                            borderRadius: BorderRadius.circular(80),
                            child: CircleAvatar(
                              radius: 68,
                              backgroundColor: AppColores.primary,
                              backgroundImage: hasPhoto
                                  ? NetworkImage(admin.foto)
                                  : null,
                              child: hasPhoto
                                  ? null
                                  : const Icon(
                                      Icons.admin_panel_settings,
                                      size: 50,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          admin.nombre.trim().isEmpty
                              ? 'Administrador'
                              : admin.nombre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColores.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Perfil del gremio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColores.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 360),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColores.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColores.borderSubtle,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: _busy
                                      ? null
                                      : () => _editarLogoGremio(admin),
                                  borderRadius: BorderRadius.circular(28),
                                  child: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppColores.grey200,
                                    backgroundImage:
                                        admin.gremioFoto.trim().isNotEmpty
                                        ? NetworkImage(admin.gremioFoto)
                                        : null,
                                    child: admin.gremioFoto.trim().isNotEmpty
                                        ? null
                                        : const Icon(
                                            Icons.shield_rounded,
                                            size: 24,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 250,
                                  ),
                                  child: Text(
                                    admin.gremio.trim().isEmpty
                                        ? 'Sin gremio configurado'
                                        : admin.gremio,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                      color: AppColores.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'Informacion de contacto',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColores.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColores.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColores.borderSubtle),
                          ),
                          child: Column(
                            children: [
                              _EditableDetailRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Nombre',
                                value: admin.nombre.trim().isEmpty
                                    ? 'Administrador'
                                    : admin.nombre,
                                onTap: _busy
                                    ? null
                                    : () => _editarNombre(admin),
                                showDivider: true,
                              ),
                              _EditableDetailRow(
                                icon: Icons.phone_outlined,
                                label: 'Telefono',
                                value: _telefonoSinPais(admin.telefono),
                                onTap: _busy
                                    ? null
                                    : () => _editarTelefono(admin),
                                showDivider: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColores.grey300),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            enabled: !_busy,
                            leading: Icon(
                              Icons.logout,
                              color: _busy
                                  ? AppColores.textSecondary
                                  : AppColores.error,
                            ),
                            title: Text(
                              'Cerrar sesion',
                              style: TextStyle(
                                color: _busy
                                    ? AppColores.textSecondary
                                    : AppColores.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: _cerrarSesion,
                          ),
                          ListTile(
                            enabled: !_busy,
                            leading: Icon(
                              Icons.delete_outline,
                              color: _busy
                                  ? AppColores.textSecondary
                                  : AppColores.error,
                            ),
                            title: Text(
                              'Eliminar cuenta',
                              style: TextStyle(
                                color: _busy
                                    ? AppColores.textSecondary
                                    : AppColores.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () => _eliminarAdministrador(admin),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.2),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EditableDetailRow extends StatelessWidget {
  const _EditableDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.showDivider,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.trim().isEmpty ? 'No disponible' : value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: AppColores.borderSubtle))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColores.primary.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: AppColores.textPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    safeValue,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColores.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_rounded,
              size: 17,
              color: AppColores.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
