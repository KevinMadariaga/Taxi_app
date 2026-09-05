import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/features/admin/admin_configuracion_screen.dart';
import 'package:taxi_app/features/admin/admin_usuario_filtros.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/widgets/confirmar_dialog.dart';
import 'package:taxi_app/widgets/dialogo_dias_membresia.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key, required this.adminId});

  final String adminId;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  String _query = '';
  final UserDataService _userDataService = UserDataService();

  // Antes `usuariosRef.snapshots()` se llamaba dentro de `build()`, que
  // corre en CADA pulsación del buscador (`setState` de abajo). `.snapshots()`
  // crea un `Stream` nuevo cada vez, y `StreamBuilder` compara por
  // referencia: veía un stream distinto en cada rebuild, cancelaba la
  // suscripción vieja y releía la colección `usuarios` entera desde cero por
  // cada letra tecleada (auditoría de bugs). El filtro de `_query` ya se
  // aplica localmente sobre `docs` dentro del builder, así que hoistear el
  // stream (una sola suscripción viva) no cambia el comportamiento de
  // búsqueda, solo deja de releer Firestore en cada tecla.
  final Stream<QuerySnapshot<Map<String, dynamic>>> _usuariosStream =
      FirebaseFirestore.instance.collection('usuarios').snapshots();

  Future<void> _aprobarMembresia({
    required String uid,
    required int dias,
    required String nombre,
  }) {
    return _userDataService.aprobarMembresiaConductor(
      uid: uid,
      dias: dias,
      nombre: nombre,
    );
  }

  Future<void> _revocarMembresia(String uid) {
    return _userDataService.revocarMembresiaConductor(uid);
  }

  Future<void> _quitarConductor(String uid) {
    return _userDataService.quitarRolConductorComoAdmin(uid);
  }

  Future<void> _deshabilitarUsuario(String uid) {
    return _userDataService.deshabilitarUsuario(uid, adminUid: widget.adminId);
  }

  Future<void> _habilitarUsuario(String uid) {
    return _userDataService.habilitarUsuario(uid);
  }

  @override
  void initState() {
    super.initState();
    SoporteNotificationService.instance.iniciarEscuchaAdmin();
    SoporteNotificationService.instance.iniciarEscuchaReportes();
    SoporteNotificationService.instance.iniciarEscuchaEmergencias();
    SoporteNotificationService.instance.iniciarEscuchaConductores();
  }

  @override
  void dispose() {
    SoporteNotificationService.instance.detenerEscuchaAdmin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColores.background,
        appBar: AppBar(
          title: const Text('Administrador'),
          backgroundColor: AppColores.primary,
          foregroundColor: AppColores.textWhite,
          actions: [
            _AdminBellIcon(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminHubScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AdminConfiguracionScreen(adminId: widget.adminId),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColores.textWhite,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Conductores'),
              Tab(text: 'Clientes'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre, teléfono o placa',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: AppColores.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _usuariosStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Error cargando usuarios: ${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? const [];

                    final conductores =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final clientes =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    for (final d in docs) {
                      final data = d.data();
                      if (!coincideBusqueda(data, _query)) continue;
                      switch (clasificarUsuario(data)) {
                        case AdminUserBucket.conductor:
                          conductores.add(d);
                        case AdminUserBucket.cliente:
                          clientes.add(d);
                      }
                    }

                    return TabBarView(
                      children: [
                        _ListaConductores(
                          docs: conductores,
                          onAprobar: _aprobarMembresia,
                          onRevocar: _revocarMembresia,
                          onQuitar: _quitarConductor,
                          onDeshabilitar: _deshabilitarUsuario,
                          onHabilitar: _habilitarUsuario,
                        ),
                        _ListaClientes(
                          docs: clientes,
                          onDeshabilitar: _deshabilitarUsuario,
                          onHabilitar: _habilitarUsuario,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


String _str(Map<String, dynamic> data, List<String> keys, String fallback) {
  for (final k in keys) {
    final v = data[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString();
  }
  return fallback;
}

String _nombreCompleto(Map<String, dynamic> data, String fallback) {
  final partes = [
    (data['nombre'] ?? '').toString().trim(),
    (data['apellido'] ?? '').toString().trim(),
  ].where((p) => p.isNotEmpty).join(' ').trim();
  return partes.isEmpty ? fallback : partes;
}

String _fechaCorta(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate();
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

void _verDetalles(BuildContext context, Map<String, dynamic> data) {
  Widget fila(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(k,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColores.textSecondary)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  final activa = membresiaActiva(data);
  final vence = data['membresiaVence'];
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(_nombreCompleto(data, 'Usuario')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fila('Teléfono', _str(data, ['telefono'], '—')),
          fila('Correo', _str(data, ['correo', 'email'], '—')),
          fila('Placa', _str(data, ['placa'], '—')),
          fila('Rol', _str(data, ['rol'], 'cliente')),
          fila('Membresía', activa ? 'activa' : 'inactiva'),
          if (activa && data['membresiaDias'] != null)
            fila('Vigencia',
                '${data['membresiaDias']} días${vence is Timestamp ? ' · vence ${_fechaCorta(vence)}' : ''}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

typedef _AprobarMembresiaCallback = Future<void> Function({
  required String uid,
  required int dias,
  required String nombre,
});

class _ListaConductores extends StatelessWidget {
  const _ListaConductores({
    required this.docs,
    required this.onAprobar,
    required this.onRevocar,
    required this.onQuitar,
    required this.onDeshabilitar,
    required this.onHabilitar,
  });
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final _AprobarMembresiaCallback onAprobar;
  final Future<void> Function(String uid) onRevocar;
  final Future<void> Function(String uid) onQuitar;
  final Future<void> Function(String uid) onDeshabilitar;
  final Future<void> Function(String uid) onHabilitar;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const _EmptyTile('No hay conductores.');
    }
    final pendientes = docs
        .where((d) =>
            d.data()['solicitudConductor'] == true &&
            !membresiaActiva(d.data()))
        .length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          children: [
            if (pendientes > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColores.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColores.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active,
                        color: AppColores.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$pendientes ${pendientes == 1 ? 'solicitud' : 'solicitudes'} de activación pendiente'
                        '${pendientes == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColores.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: docs.length,
                itemBuilder: (context, i) => _ConductorCard(
                  doc: docs[i],
                  onAprobar: onAprobar,
                  onRevocar: onRevocar,
                  onQuitar: onQuitar,
                  onDeshabilitar: onDeshabilitar,
                  onHabilitar: onHabilitar,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListaClientes extends StatelessWidget {
  const _ListaClientes({
    required this.docs,
    required this.onDeshabilitar,
    required this.onHabilitar,
  });
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Future<void> Function(String uid) onDeshabilitar;
  final Future<void> Function(String uid) onHabilitar;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const _EmptyTile('No hay clientes.');
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length,
          itemBuilder: (context, i) => _ClienteCard(
            doc: docs[i],
            onDeshabilitar: onDeshabilitar,
            onHabilitar: onHabilitar,
          ),
        ),
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          texto,
          style: const TextStyle(color: AppColores.textSecondary),
        ),
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    required this.doc,
    required this.onDeshabilitar,
    required this.onHabilitar,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function(String uid) onDeshabilitar;
  final Future<void> Function(String uid) onHabilitar;

  Future<void> _deshabilitar(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Deshabilitar usuario',
      mensaje:
          '$nombre no podrá volver a entrar a la app hasta que se lo habilite de nuevo.',
      accion: 'Deshabilitar',
      peligro: true,
    );
    if (!ok) return;
    await onDeshabilitar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre deshabilitado.')),
      );
    }
  }

  Future<void> _habilitar(BuildContext context, String nombre) async {
    await onHabilitar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre habilitado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final nombre = _nombreCompleto(data, 'Cliente');
    final contacto =
        _str(data, ['correo', 'email', 'telefono'], 'Sin contacto');
    final foto = _str(data, ['foto', 'fotoUrl'], '');
    final deshabilitado = data['deshabilitado'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColores.grey200,
          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
          onBackgroundImageError: foto.isNotEmpty ? (_, _) {} : null,
          child: foto.isEmpty ? const Icon(Icons.person) : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (deshabilitado) ...[
              const SizedBox(width: 6),
              const _BadgeDeshabilitado(),
            ],
          ],
        ),
        subtitle: Text(contacto),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            // Sin esto, al cerrarse el menú y reconstruirse la card (la
            // lista completa viene de un `StreamBuilder` que reemite en
            // cuanto la acción escribe en Firestore), el foco caía por
            // defecto en el buscador de arriba y abría el teclado solo —
            // visto en dispositivo real al tocar "Habilitar usuario".
            FocusScope.of(context).unfocus();
            if (v == 'detalles') _verDetalles(context, data);
            if (v == 'deshabilitar') _deshabilitar(context, nombre);
            if (v == 'habilitar') _habilitar(context, nombre);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'detalles', child: Text('Ver detalles')),
            if (deshabilitado)
              const PopupMenuItem(
                  value: 'habilitar', child: Text('Habilitar usuario'))
            else
              const PopupMenuItem(
                  value: 'deshabilitar',
                  child: Text('Deshabilitar usuario')),
          ],
        ),
      ),
    );
  }
}

class _BadgeDeshabilitado extends StatelessWidget {
  const _BadgeDeshabilitado();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColores.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Deshabilitado',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColores.error,
        ),
      ),
    );
  }
}

class _ConductorCard extends StatelessWidget {
  const _ConductorCard({
    required this.doc,
    required this.onAprobar,
    required this.onRevocar,
    required this.onQuitar,
    required this.onDeshabilitar,
    required this.onHabilitar,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final _AprobarMembresiaCallback onAprobar;
  final Future<void> Function(String uid) onRevocar;
  final Future<void> Function(String uid) onQuitar;
  final Future<void> Function(String uid) onDeshabilitar;
  final Future<void> Function(String uid) onHabilitar;

  Future<void> _aprobar(BuildContext context, String nombre) async {
    final pidio = doc.data()['solicitudConductor'] == true;
    if (!pidio) {
      final ok = await mostrarConfirmacion(
        context,
        titulo: 'Activar sin solicitud',
        mensaje:
            '$nombre no solicitó la activación. ¿Activar de todas formas?',
        accion: 'Activar',
      );
      if (!ok) return;
      if (!context.mounted) return;
    }
    final dias = await mostrarDialogoDiasMembresia(context);
    if (dias == null) return;
    await onAprobar(uid: doc.id, dias: dias, nombre: nombre);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Membresía activada para $nombre ($dias días).'),
          backgroundColor: AppColores.success,
        ),
      );
    }
  }

  Future<void> _revocar(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Revocar membresía',
      mensaje: 'Se desactivará el servicio de $nombre. Tendrá que activar de nuevo.',
      accion: 'Revocar',
      peligro: true,
    );
    if (!ok) return;
    await onRevocar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Membresía de $nombre revocada.')),
      );
    }
  }

  Future<void> _quitarConductor(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Quitar como conductor',
      mensaje: '$nombre volverá a ser cliente. Se desactiva su servicio.',
      accion: 'Quitar',
      peligro: true,
    );
    if (!ok) return;
    await onQuitar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre pasó a cliente.')),
      );
    }
  }

  Future<void> _deshabilitar(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Deshabilitar usuario',
      mensaje:
          '$nombre no podrá volver a entrar a la app hasta que se lo habilite de nuevo.',
      accion: 'Deshabilitar',
      peligro: true,
    );
    if (!ok) return;
    await onDeshabilitar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre deshabilitado.')),
      );
    }
  }

  Future<void> _habilitar(BuildContext context, String nombre) async {
    await onHabilitar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre habilitado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final nombre = _nombreCompleto(data, 'Conductor');
    final placa = _str(data, ['placa'], 'Sin placa');
    final foto = _str(data, ['foto', 'fotoUrl'], '');
    final activa = membresiaActiva(data);
    final pidio = data['solicitudConductor'] == true;
    final dias = data['membresiaDias'];
    final vence = data['membresiaVence'];
    final deshabilitado = data['deshabilitado'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColores.grey200,
                  backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                  onBackgroundImageError: foto.isNotEmpty ? (_, _) {} : null,
                  child:
                      foto.isEmpty ? const Icon(Icons.local_taxi) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(nombre,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (deshabilitado) ...[
                            const SizedBox(width: 6),
                            const _BadgeDeshabilitado(),
                          ],
                        ],
                      ),
                      Text('Placa: $placa',
                          style: const TextStyle(
                              color: AppColores.textSecondary)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    FocusScope.of(context).unfocus();
                    if (v == 'detalles') _verDetalles(context, data);
                    if (v == 'revocar') _revocar(context, nombre);
                    if (v == 'quitar') _quitarConductor(context, nombre);
                    if (v == 'deshabilitar') _deshabilitar(context, nombre);
                    if (v == 'habilitar') _habilitar(context, nombre);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'detalles', child: Text('Ver detalles')),
                    if (activa)
                      const PopupMenuItem(
                          value: 'revocar', child: Text('Revocar membresía')),
                    const PopupMenuItem(
                        value: 'quitar', child: Text('Quitar como conductor')),
                    if (deshabilitado)
                      const PopupMenuItem(
                          value: 'habilitar', child: Text('Habilitar usuario'))
                    else
                      const PopupMenuItem(
                          value: 'deshabilitar',
                          child: Text('Deshabilitar usuario')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (activa)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColores.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified,
                            color: AppColores.success, size: 18),
                        SizedBox(width: 6),
                        Text('Membresía: activa',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColores.success)),
                      ],
                    ),
                    if (dias != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Vigencia: $dias días'
                          '${vence is Timestamp ? ' · vence ${_fechaCorta(vence)}' : ''}',
                          style: const TextStyle(
                              color: AppColores.textSecondary),
                        ),
                      ),
                  ],
                ),
              )
            else if (pidio)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColores.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.notifications_active,
                            color: AppColores.warning, size: 18),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Quiere activar el servicio de conductor',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColores.success,
                        foregroundColor: AppColores.textWhite,
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar y activar membresía'),
                      onPressed: () => _aprobar(context, nombre),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColores.textSecondary, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Registrado · sin solicitud de activación',
                      style: TextStyle(color: AppColores.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _aprobar(context, nombre),
                    child: const Text('Activar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── BELL BADGE ──────────────────────────────────────────────────────────────

class _AdminBellIcon extends StatefulWidget {
  const _AdminBellIcon({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AdminBellIcon> createState() => _AdminBellIconState();
}

class _AdminBellIconState extends State<_AdminBellIcon> {
  int _chats = 0;
  int _reportes = 0;

  StreamSubscription<QuerySnapshot>? _chatsSub;
  StreamSubscription<QuerySnapshot>? _reportesSub;

  int get _total => _chats + _reportes;

  @override
  void initState() {
    super.initState();
    final fs = FirebaseFirestore.instance;

    _chatsSub = fs
        .collection('soporte_chats')
        .where('hayMensajesNuevosAdmin', isEqualTo: true)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() => _chats = snap.docs.length);
          },
          onError: (e, st) =>
              ErrorReporter.report(e, st, reason: 'AdminBellIcon: chats'),
        );

    _reportesSub = fs
        .collection('reportes')
        .where('visto', isEqualTo: false)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() => _reportes = snap.docs.length);
          },
          onError: (e, st) =>
              ErrorReporter.report(e, st, reason: 'AdminBellIcon: reportes'),
        );
  }

  @override
  void dispose() {
    _chatsSub?.cancel();
    _reportesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _total;
    // Las solicitudes de activación de conductor NO suman acá a propósito:
    // esta campana lleva a `AdminHubScreen` (Gestión: Reportes/Mensajes/
    // Sugerencias), que no tiene ninguna pestaña de activaciones — un
    // conteo que incluyera esas solicitudes nunca bajaba por más que el
    // admin "leyera todo" en Gestión, porque ahí no hay nada que hacer con
    // ellas. Esas se ven y se resuelven en la pestaña "Conductores" de este
    // mismo panel (banner de pendientes + botón "Activar").
    return IconButton(
      tooltip: 'Notificaciones — Mensajes y Reportes',
      onPressed: widget.onTap,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_rounded),
          if (count > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints:
                    const BoxConstraints(minWidth: 17, minHeight: 17),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
