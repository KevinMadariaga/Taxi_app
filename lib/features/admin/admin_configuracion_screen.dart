import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/auth_service.dart';
import 'package:taxi_app/routes/app_routes.dart';

/// Configuración del administrador: foto, nombre y cerrar sesión.
/// Los datos se leen de `administradores/{uid}` con respaldo en `usuarios/{uid}`.
class AdminConfiguracionScreen extends StatefulWidget {
  const AdminConfiguracionScreen({super.key, required this.adminId});

  final String adminId;

  @override
  State<AdminConfiguracionScreen> createState() =>
      _AdminConfiguracionScreenState();
}

class _AdminConfiguracionScreenState extends State<AdminConfiguracionScreen> {
  bool _busy = false;
  late Future<_AdminInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<_AdminInfo> _cargar() async {
    final fs = FirebaseFirestore.instance;
    final adminSnap =
        await fs.collection('administradores').doc(widget.adminId).get();
    final userSnap =
        await fs.collection('usuarios').doc(widget.adminId).get();
    final a = adminSnap.data() ?? const <String, dynamic>{};
    final u = userSnap.data() ?? const <String, dynamic>{};

    String first(List<dynamic> vals) {
      for (final v in vals) {
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      return '';
    }

    final nombre = first([
      a['nombre'],
      [u['nombre'], u['apellido']]
          .where((p) => p != null && p.toString().trim().isNotEmpty)
          .join(' ')
          .trim(),
    ]);

    return _AdminInfo(
      nombre: nombre.isEmpty ? 'Administrador' : nombre,
      foto: first([a['foto'], u['foto'], u['fotoUrl']]),
      correo: first([a['email'], u['correo'], u['email']]),
      gremio: first([a['gremio']]),
    );
  }

  Future<void> _cerrarSesion() async {
    if (_busy) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres cerrar sesión?'),
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
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: AppColores.primary,
        foregroundColor: AppColores.textWhite,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: FutureBuilder<_AdminInfo>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final info = snapshot.data ??
                    const _AdminInfo(
                      nombre: 'Administrador',
                      foto: '',
                      correo: '',
                      gremio: '',
                    );

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      _PerfilCard(info: info),
                      const SizedBox(height: 16),
                      _InfoTile(
                        icon: Icons.shield_outlined,
                        titulo: 'Rol',
                        valor: 'Administrador',
                      ),
                      if (info.correo.isNotEmpty)
                        _InfoTile(
                          icon: Icons.email_outlined,
                          titulo: 'Correo',
                          valor: info.correo,
                        ),
                      if (info.gremio.isNotEmpty)
                        _InfoTile(
                          icon: Icons.groups_outlined,
                          titulo: 'Gremio',
                          valor: info.gremio,
                        ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _cerrarSesion,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColores.textWhite,
                                  ),
                                ),
                              )
                            : const Icon(Icons.logout),
                        label: const Text('Cerrar sesión'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColores.buttonCancel,
                          foregroundColor: AppColores.textWhite,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminInfo {
  const _AdminInfo({
    required this.nombre,
    required this.foto,
    required this.correo,
    required this.gremio,
  });
  final String nombre;
  final String foto;
  final String correo;
  final String gremio;
}

class _PerfilCard extends StatelessWidget {
  const _PerfilCard({required this.info});
  final _AdminInfo info;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: AppColores.grey200,
              backgroundImage:
                  info.foto.isNotEmpty ? NetworkImage(info.foto) : null,
              child: info.foto.isEmpty
                  ? const Icon(Icons.admin_panel_settings, size: 52)
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              info.nombre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColores.primary.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Administrador',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColores.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.titulo,
    required this.valor,
  });
  final IconData icon;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColores.primary),
        title: Text(titulo,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(valor, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
