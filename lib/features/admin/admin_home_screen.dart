import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/features/admin/admin_configuracion_screen.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key, required this.adminId});

  final String adminId;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  String _query = '';
  final UserDataService _userDataService = UserDataService();

  Future<void> _aprobarMembresia({
    required String uid,
    required int dias,
    required String nombre,
    String? fcmToken,
  }) {
    return _userDataService.aprobarMembresiaConductor(
      uid: uid,
      dias: dias,
      nombre: nombre,
      fcmToken: fcmToken,
    );
  }

  Future<void> _revocarMembresia(String uid) {
    return _userDataService.revocarMembresiaConductor(uid);
  }

  Future<void> _quitarConductor(String uid) {
    return _userDataService.quitarRolConductorComoAdmin(uid);
  }

  Future<void> _eliminarUsuario(String uid) {
    return _userDataService.eliminarUsuario(uid);
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

  bool _coincide(Map<String, dynamic> data) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final nombre = '${data['nombre'] ?? ''} ${data['apellido'] ?? ''}'
        .toLowerCase();
    return nombre.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final usuariosRef = FirebaseFirestore.instance.collection('usuarios');

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
                        hintText: 'Buscar por nombre o apellido',
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
                  stream: usuariosRef.snapshots(),
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
                      if (!_coincide(data)) continue;
                      final rol = (data['rol'] ?? '').toString().toLowerCase();
                      final pidioConductor = data['solicitudConductor'] == true;
                      if (rol == 'conductor' || pidioConductor) {
                        conductores.add(d);
                      } else if (rol == 'cliente' || rol.isEmpty) {
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
                          onEliminar: _eliminarUsuario,
                        ),
                        _ListaClientes(
                          docs: clientes,
                          onEliminar: _eliminarUsuario,
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

/// Una membresía está activa solo si el campo dice 'activa' **y** la fecha de
/// vencimiento no pasó. Mirar solo `membresia` no alcanza: la expiración la
/// hace un job programado server-side, así que entre el vencimiento real y el
/// barrido (o si el barrido falla) el campo sigue diciendo 'activa'. Mismo
/// criterio que la transacción de `InicioConductorViewModel.aceptarSolicitud`,
/// que es la que de verdad bloquea tomar viajes.
bool _membresiaActiva(Map<String, dynamic> data) {
  final activa = (data['membresia'] ?? '').toString().toLowerCase() == 'activa';
  if (!activa) return false;
  final vence = data['membresiaVence'];
  if (vence is Timestamp && vence.toDate().isBefore(DateTime.now())) {
    return false;
  }
  return true;
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

Future<bool> _confirmar(
  BuildContext context,
  String titulo,
  String mensaje, {
  String accion = 'Aceptar',
  bool peligro = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: peligro
              ? FilledButton.styleFrom(backgroundColor: AppColores.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return r == true;
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

  final activa = _membresiaActiva(data);
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
  String? fcmToken,
});

class _ListaConductores extends StatelessWidget {
  const _ListaConductores({
    required this.docs,
    required this.onAprobar,
    required this.onRevocar,
    required this.onQuitar,
    required this.onEliminar,
  });
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final _AprobarMembresiaCallback onAprobar;
  final Future<void> Function(String uid) onRevocar;
  final Future<void> Function(String uid) onQuitar;
  final Future<void> Function(String uid) onEliminar;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return const _EmptyTile('No hay conductores.');
    }
    final pendientes = docs
        .where((d) =>
            d.data()['solicitudConductor'] == true &&
            !_membresiaActiva(d.data()))
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
                  onEliminar: onEliminar,
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
  const _ListaClientes({required this.docs, required this.onEliminar});
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Future<void> Function(String uid) onEliminar;

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
          itemBuilder: (context, i) =>
              _ClienteCard(doc: docs[i], onEliminar: onEliminar),
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
  const _ClienteCard({required this.doc, required this.onEliminar});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function(String uid) onEliminar;

  Future<void> _eliminar(BuildContext context, String nombre) async {
    final ok = await _confirmar(
      context,
      'Eliminar usuario',
      'Se eliminará el registro de $nombre. Esta acción no se puede deshacer.',
      accion: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    await onEliminar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre eliminado.')),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColores.grey200,
          backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
          child: foto.isEmpty ? const Icon(Icons.person) : null,
        ),
        title: Text(nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(contacto),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'detalles') _verDetalles(context, data);
            if (v == 'eliminar') _eliminar(context, nombre);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'detalles', child: Text('Ver detalles')),
            PopupMenuItem(value: 'eliminar', child: Text('Eliminar usuario')),
          ],
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
    required this.onEliminar,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final _AprobarMembresiaCallback onAprobar;
  final Future<void> Function(String uid) onRevocar;
  final Future<void> Function(String uid) onQuitar;
  final Future<void> Function(String uid) onEliminar;

  Future<int?> _pedirDias(BuildContext context) {
    final controller = TextEditingController(text: '30');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activar membresía'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Por cuántos días se activa el servicio?'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Días',
                suffixText: 'días',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColores.buttonPrimary,
              foregroundColor: AppColores.textWhite,
            ),
            onPressed: () {
              final dias = int.tryParse(controller.text.trim());
              if (dias == null || dias <= 0) return;
              Navigator.pop(ctx, dias);
            },
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  Future<void> _aprobar(BuildContext context, String nombre) async {
    final dias = await _pedirDias(context);
    if (dias == null) return;
    final conductorToken = (doc.data()['fcmToken'] as String?) ?? '';
    await onAprobar(
      uid: doc.id,
      dias: dias,
      nombre: nombre,
      fcmToken: conductorToken,
    );

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
    final ok = await _confirmar(
      context,
      'Revocar membresía',
      'Se desactivará el servicio de $nombre. Tendrá que activar de nuevo.',
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
    final ok = await _confirmar(
      context,
      'Quitar como conductor',
      '$nombre volverá a ser cliente. Se desactiva su servicio.',
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

  Future<void> _eliminar(BuildContext context, String nombre) async {
    final ok = await _confirmar(
      context,
      'Eliminar usuario',
      'Se eliminará el registro de $nombre. Esta acción no se puede deshacer.',
      accion: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    await onEliminar(doc.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nombre eliminado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final nombre = _nombreCompleto(data, 'Conductor');
    final placa = _str(data, ['placa'], 'Sin placa');
    final foto = _str(data, ['foto', 'fotoUrl'], '');
    final activa = _membresiaActiva(data);
    final pidio = data['solicitudConductor'] == true;
    final dias = data['membresiaDias'];
    final vence = data['membresiaVence'];

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
                  child:
                      foto.isEmpty ? const Icon(Icons.local_taxi) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Placa: $placa',
                          style: const TextStyle(
                              color: AppColores.textSecondary)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'detalles') _verDetalles(context, data);
                    if (v == 'revocar') _revocar(context, nombre);
                    if (v == 'quitar') _quitarConductor(context, nombre);
                    if (v == 'eliminar') _eliminar(context, nombre);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'detalles', child: Text('Ver detalles')),
                    if (activa)
                      const PopupMenuItem(
                          value: 'revocar', child: Text('Revocar membresía')),
                    const PopupMenuItem(
                        value: 'quitar', child: Text('Quitar como conductor')),
                    const PopupMenuItem(
                        value: 'eliminar', child: Text('Eliminar usuario')),
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
  int _conductores = 0;

  StreamSubscription<QuerySnapshot>? _chatsSub;
  StreamSubscription<QuerySnapshot>? _reportesSub;
  StreamSubscription<QuerySnapshot>? _conductoresSub;

  int get _total => _chats + _reportes + _conductores;

  @override
  void initState() {
    super.initState();
    final fs = FirebaseFirestore.instance;

    _chatsSub = fs
        .collection('soporte_chats')
        .where('hayMensajesNuevosAdmin', isEqualTo: true)
        .snapshots()
        .listen((snap) => setState(() => _chats = snap.docs.length));

    _reportesSub = fs
        .collection('reportes')
        .where('visto', isEqualTo: false)
        .snapshots()
        .listen((snap) => setState(() => _reportes = snap.docs.length));

    _conductoresSub = fs
        .collection('usuarios')
        .where('solicitudConductor', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      // Mismo criterio que `_membresiaActiva` (incluye vencimiento) en vez de
      // duplicar acá una comprobación que solo mira el campo `membresia`.
      final pendientes = snap.docs
          .where((d) => !_membresiaActiva(d.data()))
          .length;
      setState(() => _conductores = pendientes);
    });
  }

  @override
  void dispose() {
    _chatsSub?.cancel();
    _reportesSub?.cancel();
    _conductoresSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _total;
    return IconButton(
      tooltip: 'Notificaciones — Mensajes, Reportes y Activaciones',
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
