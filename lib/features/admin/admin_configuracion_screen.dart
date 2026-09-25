import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/services/auth_service.dart';
import 'package:taxi_app/routes/app_routes.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';

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
    final adminSnap = await fs
        .collection('administradores')
        .doc(widget.adminId)
        .get();
    final userSnap = await fs.collection('usuarios').doc(widget.adminId).get();
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

    final confirmar = await mostrarConfirmacion(
      context,
      titulo: 'Cerrar sesión',
      mensaje: '¿Quieres cerrar sesión en esta cuenta de administrador?',
      accion: 'Cerrar sesión',
      peligro: true,
      icono: Icons.logout_rounded,
    );

    if (confirmar != true || !mounted) return;

    setState(() => _busy = true);

    // Navegar ANTES de cerrar sesión: desmontar el árbol cancela los listeners
    // de Firestore en sus `dispose()`. Al revés, el `signOut()` los dejaba
    // suscritos sin autenticación y reventaban con `permission-denied`
    // (el panel de admin escucha reportes, emergencias y chats de soporte).
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);

    // Sin `context` de acá en adelante: este State ya fue desmontado.
    await AuthService().logout();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Configuración'),
      body: FutureBuilder<_AdminInfo>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final info =
              snapshot.data ??
              const _AdminInfo(
                nombre: 'Administrador',
                foto: '',
                correo: '',
                gremio: '',
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PerfilCard(info: info),
                      const SizedBox(height: 24),
                      SeccionAgrupada(
                        titulo: 'Cuenta',
                        children: [
                          const FilaDato(
                            icono: Icons.shield_outlined,
                            etiqueta: 'Rol',
                            valor: 'Administrador',
                          ),
                          if (info.correo.isNotEmpty)
                            FilaDato(
                              icono: Icons.alternate_email_rounded,
                              etiqueta: 'Correo',
                              valor: info.correo,
                            ),
                          if (info.gremio.isNotEmpty)
                            FilaDato(
                              icono: Icons.groups_outlined,
                              etiqueta: 'Gremio',
                              valor: info.gremio,
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SeccionAgrupada(
                        titulo: 'Sesión',
                        children: [
                          FilaOpcion(
                            icono: Icons.logout_rounded,
                            titulo: _busy
                                ? 'Cerrando sesión…'
                                : 'Cerrar sesión',
                            peligro: true,
                            trailing: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            onTap: _busy ? null : _cerrarSesion,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
    final palette = context.palette;
    final px = (104 * MediaQuery.devicePixelRatioOf(context)).round();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColores.brand400, AppColores.brand500],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.background,
            ),
            child: CircleAvatar(
              radius: 52,
              backgroundColor: palette.grey200,
              backgroundImage: info.foto.isNotEmpty
                  ? ResizeImage(NetworkImage(info.foto), width: px, height: px)
                  : null,
              child: info.foto.isEmpty
                  ? Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 48,
                      color: palette.textSecondary,
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          info.nombre,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColores.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 15,
                color: acentoMarca(context),
              ),
              const SizedBox(width: 6),
              Text(
                'Administrador',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
