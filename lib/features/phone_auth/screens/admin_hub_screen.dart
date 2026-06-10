import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';

import 'soporte_chat_detalle_admin_screen.dart';

class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  int _usuarios = 0;
  int _reportes = 0;
  int _mensajes = 0;

  StreamSubscription<QuerySnapshot>? _usuariosSub;
  StreamSubscription<QuerySnapshot>? _reportesSub;
  StreamSubscription<QuerySnapshot>? _mensajesSub;

  @override
  void initState() {
    super.initState();
    final fs = FirebaseFirestore.instance;

    _usuariosSub = fs
        .collection('usuarios')
        .where('solicitudConductor', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final count = snap.docs.where((d) {
        final m = (d.data()['membresia'] ?? '').toString().toLowerCase();
        return m != 'activa';
      }).length;
      setState(() => _usuarios = count);
    });

    _reportesSub = fs
        .collection('reportes')
        .where('visto', isEqualTo: false)
        .snapshots()
        .listen((snap) => setState(() => _reportes = snap.docs.length));

    _mensajesSub = fs
        .collection('soporte_chats')
        .where('hayMensajesNuevosAdmin', isEqualTo: true)
        .snapshots()
        .listen((snap) => setState(() => _mensajes = snap.docs.length));
  }

  @override
  void dispose() {
    _usuariosSub?.cancel();
    _reportesSub?.cancel();
    _mensajesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: AppColores.background,
        appBar: AppBar(
          backgroundColor: AppColores.background,
          foregroundColor: AppColores.textPrimary,
          elevation: 0,
          title: const Text(
            'Gestión',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bottom: TabBar(
            labelColor: AppColores.textPrimary,
            unselectedLabelColor: AppColores.textSecondary,
            indicatorColor: AppColores.primary,
            tabs: [
              _BadgeTab(label: 'Usuarios', count: _usuarios),
              _BadgeTab(label: 'Reportes', count: _reportes),
              _BadgeTab(label: 'Mensajes', count: _mensajes),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TabUsuarios(),
            _TabReportes(),
            _TabMensajes(),
          ],
        ),
      ),
    );
  }
}

class _BadgeTab extends StatelessWidget {
  const _BadgeTab({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── TAB USUARIOS ────────────────────────────────────────────────────────────

class _TabUsuarios extends StatelessWidget {
  const _TabUsuarios();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .where('tipoUsuario', whereIn: ['cliente', 'conductor'])
          .orderBy('nombre')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Sin usuarios registrados.',
              style: TextStyle(color: AppColores.textSecondary),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final nombre = (data['nombre'] ?? 'Sin nombre').toString();
            final apellido = (data['apellido'] ?? '').toString();
            final tipo = (data['tipoUsuario'] ?? data['rol'] ?? '').toString();
            final telefono = (data['telefono'] ?? '').toString();
            final foto = (data['foto'] ?? data['fotoUrl'] ?? '').toString();
            final esConductor = tipo == 'conductor';

            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: AppColores.surface,
              leading: CircleAvatar(
                backgroundColor: esConductor
                    ? AppColores.primary.withValues(alpha: 0.18)
                    : AppColores.grey200,
                backgroundImage:
                    foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty
                    ? Icon(
                        esConductor ? Icons.local_taxi : Icons.person,
                        color: esConductor
                            ? AppColores.textPrimary
                            : AppColores.textSecondary,
                      )
                    : null,
              ),
              title: Text(
                apellido.isNotEmpty ? '$nombre $apellido' : nombre,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                telefono.isNotEmpty ? telefono : tipo,
                style: const TextStyle(color: AppColores.textSecondary),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: esConductor
                      ? AppColores.primary.withValues(alpha: 0.15)
                      : AppColores.grey200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  esConductor ? 'Conductor' : 'Cliente',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: esConductor
                        ? const Color(0xFF7A6000)
                        : AppColores.textSecondary,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─── TAB REPORTES ────────────────────────────────────────────────────────────

class _TabReportes extends StatelessWidget {
  const _TabReportes();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reportes')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Sin reportes registrados.',
              style: TextStyle(color: AppColores.textSecondary),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final conductor = (data['conductor'] ?? 'Conductor desconocido')
                .toString();
            final motivos = (data['motivos'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final comentario = (data['comentario'] ?? '').toString();
            final ts = data['createdAt'] as Timestamp?;
            final fecha = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '';
            final visto = data['visto'] as bool? ?? false;

            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: visto ? AppColores.surface : AppColores.primary.withValues(alpha: 0.06),
              leading: CircleAvatar(
                backgroundColor: visto ? AppColores.grey200 : AppColores.primary,
                child: Icon(
                  Icons.flag_rounded,
                  color: visto ? AppColores.textSecondary : AppColores.textPrimary,
                ),
              ),
              title: Text(
                'Conductor: $conductor',
                style: TextStyle(
                  fontWeight: visto ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (motivos.isNotEmpty)
                    Text(
                      motivos.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColores.textSecondary,
                      ),
                    ),
                  if (comentario.isNotEmpty)
                    Text(
                      comentario,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    fecha,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  if (!visto)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColores.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              onTap: () async {
                if (!visto) {
                  await FirebaseFirestore.instance
                      .collection('reportes')
                      .doc(docs[index].id)
                      .update({'visto': true});
                }
                if (context.mounted) {
                  _mostrarDetalleReporte(
                    context,
                    conductor: conductor,
                    motivos: motivos,
                    comentario: comentario,
                    fecha: fecha,
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  void _mostrarDetalleReporte(
    BuildContext context, {
    required String conductor,
    required List<String> motivos,
    required String comentario,
    required String fecha,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColores.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: AppColores.error),
                const SizedBox(width: 8),
                const Text(
                  'Detalle del reporte',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  fecha,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColores.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detalleRow('Conductor', conductor),
            const SizedBox(height: 8),
            _detalleRow('Motivos', motivos.join(', ')),
            if (comentario.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detalleRow('Comentario', comentario),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detalleRow(String label, String value) {
    return Column(
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
          value,
          style: const TextStyle(fontSize: 15),
        ),
      ],
    );
  }
}

// ─── TAB MENSAJES ─────────────────────────────────────────────────────────────

class _TabMensajes extends StatelessWidget {
  const _TabMensajes();

  @override
  Widget build(BuildContext context) {
    final service = SoporteChatService();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchTodosChats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'Sin chats de soporte activos.',
              style: TextStyle(color: AppColores.textSecondary),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final userId = data['userId'] as String? ?? docs[index].id;
            final userName = data['userName'] as String? ?? 'Usuario';
            final userType = data['userType'] as String? ?? 'cliente';
            final ultimoMensaje = data['ultimoMensaje'] as String? ?? '';
            final hayNuevos =
                data['hayMensajesNuevosAdmin'] as bool? ?? false;
            final ts = data['ultimoMensajeAt'] as Timestamp?;
            final hora = ts != null
                ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '';

            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: AppColores.surface,
              leading: CircleAvatar(
                backgroundColor:
                    hayNuevos ? AppColores.primary : AppColores.grey200,
                child: Icon(
                  userType == 'conductor'
                      ? Icons.local_taxi
                      : Icons.person,
                  color: hayNuevos
                      ? AppColores.textPrimary
                      : AppColores.textSecondary,
                ),
              ),
              title: Text(
                userName,
                style: TextStyle(
                  fontWeight:
                      hayNuevos ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              subtitle: Text(
                ultimoMensaje,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hayNuevos
                      ? AppColores.textPrimary
                      : AppColores.textSecondary,
                  fontWeight:
                      hayNuevos ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hora,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  if (hayNuevos)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColores.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SoporteChatDetalleAdminScreen(
                      userId: userId,
                      userName: userName,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
