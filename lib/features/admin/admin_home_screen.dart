import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/services/soporte_notification_service.dart';
import 'package:taxi_app/core/services/sugerencias_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/features/admin/admin_configuracion_screen.dart';
import 'package:taxi_app/features/admin/admin_usuario_filtros.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/features/phone_auth/services/user_data_service.dart';
import 'package:taxi_app/core/validators/vehiculo_validator.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';
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
    // Primero los marcadores de "ya notificado", o al reabrir el panel
    // vuelven a salir las emergencias y reportes que el admin ya vio.
    unawaited(
      SoporteNotificationService.instance.cargarUltimosVistos().then((_) {
        SoporteNotificationService.instance.iniciarEscuchaAdmin();
        SoporteNotificationService.instance.iniciarEscuchaReportes();
        SoporteNotificationService.instance.iniciarEscuchaEmergencias();
        SoporteNotificationService.instance.iniciarEscuchaConductores();
        SoporteNotificationService.instance.iniciarEscuchaSugerencias();
      }),
    );
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
        backgroundColor: context.palette.background,
        appBar: appBarNeutra(
          context,
          titulo: 'Administrador',
          actions: [
            _AdminBellIcon(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AdminHubScreen())),
            ),
            IconButton(
              tooltip: 'Configuración',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AdminConfiguracionScreen(adminId: widget.adminId),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          bottom: tabBarNeutra(
            context,
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
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      cursorColor: AppColores.primary,
                      style: TextStyle(color: context.palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre, teléfono o placa',
                        hintStyle: TextStyle(
                          color: context.palette.textSecondary,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: context.palette.textSecondary,
                        ),
                        filled: true,
                        fillColor: context.palette.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: context.palette.borderSubtle,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppColores.primary,
                            width: 1.8,
                          ),
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
                      return const _EmptyTile(
                        icono: Icons.cloud_off_rounded,
                        titulo: 'No se pudieron cargar los usuarios',
                        detalle: 'Revisa tu conexión e inténtalo de nuevo.',
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
  final activa = membresiaActiva(data);
  final vence = data['membresiaVence'];
  final rol = _str(data, ['rol'], 'cliente').toLowerCase();
  final esConductor = rol == 'conductor';
  final foto = _str(data, ['foto', 'fotoUrl'], '');
  final vehiculo = VehiculoValidator.descripcion(
    data['modeloVehiculo']?.toString(),
    data['colorVehiculo']?.toString(),
  );
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final palette = ctx.palette;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _Avatar(
                    foto: foto,
                    radio: 36,
                    esConductor: esConductor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _nombreCompleto(data, 'Usuario'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  esConductor ? 'Conductor' : 'Cliente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                SeccionAgrupada(
                  titulo: 'Contacto',
                  children: [
                    FilaDato(
                      icono: Icons.phone_iphone_rounded,
                      etiqueta: 'Celular',
                      valor: _str(data, ['telefono'], '—'),
                    ),
                    FilaDato(
                      icono: Icons.alternate_email_rounded,
                      etiqueta: 'Correo',
                      valor: _str(data, ['correo', 'email'], '—'),
                    ),
                  ],
                ),
                if (esConductor) ...[
                  const SizedBox(height: 16),
                  SeccionAgrupada(
                    titulo: 'Vehículo',
                    children: [
                      FilaDato(
                        icono: Icons.pin_outlined,
                        etiqueta: 'Placa',
                        valor: _str(data, ['placa'], '—'),
                      ),
                      FilaDato(
                        icono: Icons.directions_car_outlined,
                        etiqueta: 'Modelo y color',
                        valor: vehiculo.isEmpty ? '—' : vehiculo,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SeccionAgrupada(
                    titulo: 'Membresía',
                    children: [
                      FilaDato(
                        icono: activa
                            ? Icons.workspace_premium_rounded
                            : Icons.lock_clock_outlined,
                        etiqueta: 'Estado',
                        valor: activa ? 'Activa' : 'Inactiva',
                      ),
                      if (activa && data['membresiaDias'] != null)
                        FilaDato(
                          icono: Icons.event_rounded,
                          etiqueta: 'Vigencia',
                          valor:
                              '${data['membresiaDias']} días${vence is Timestamp ? ' · vence ${_fechaCorta(vence)}' : ''}',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

typedef _AprobarMembresiaCallback =
    Future<void> Function({
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
      return const _EmptyTile(
        icono: Icons.local_taxi_outlined,
        titulo: 'No hay conductores',
        detalle: 'Aquí aparecen los usuarios que se registran como conductor.',
      );
    }
    final pendientes = docs
        .where(
          (d) =>
              d.data()['solicitudConductor'] == true &&
              !membresiaActiva(d.data()),
        )
        .length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          itemCount: docs.length + (pendientes > 0 ? 1 : 0),
          itemBuilder: (context, i) {
            if (pendientes > 0 && i == 0) {
              return _AvisoPendientes(pendientes: pendientes);
            }
            return _ConductorCard(
              doc: docs[i - (pendientes > 0 ? 1 : 0)],
              onAprobar: onAprobar,
              onRevocar: onRevocar,
              onQuitar: onQuitar,
              onDeshabilitar: onDeshabilitar,
              onHabilitar: onHabilitar,
            );
          },
        ),
      ),
    );
  }
}

class _AvisoPendientes extends StatelessWidget {
  const _AvisoPendientes({required this.pendientes});

  final int pendientes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppColores.warning.withValues(alpha: 0.14),
          palette.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColores.warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColores.warning.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: AppColores.warning,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pendientes == 1
                  ? '1 conductor espera activación'
                  : '$pendientes conductores esperan activación',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
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
      return const _EmptyTile(
        icono: Icons.people_outline_rounded,
        titulo: 'No hay clientes',
        detalle: 'Aquí aparecen los pasajeros registrados.',
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
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
  const _EmptyTile({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });
  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: EncabezadoIcono(
          icono: icono,
          titulo: titulo,
          descripcion: detalle,
        ),
      ),
    );
  }
}

/// Foto (decodificada al tamaño del avatar) o ícono si no hay.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.foto,
    required this.radio,
    required this.esConductor,
  });

  final String foto;
  final double radio;
  final bool esConductor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final px = (radio * 2 * MediaQuery.devicePixelRatioOf(context)).round();
    return CircleAvatar(
      radius: radio,
      backgroundColor: palette.grey200,
      backgroundImage: foto.isNotEmpty
          ? ResizeImage(NetworkImage(foto), width: px, height: px)
          : null,
      onBackgroundImageError: foto.isNotEmpty ? (_, _) {} : null,
      child: foto.isEmpty
          ? Icon(
              esConductor ? Icons.local_taxi_rounded : Icons.person_rounded,
              color: palette.textSecondary,
              size: radio,
            )
          : null,
    );
  }
}

/// Contenedor común de las tarjetas de usuario.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: child,
    );
  }
}

/// Menú "⋮" de cada tarjeta, con íconos.
PopupMenuButton<String> _menuAcciones(
  BuildContext context, {
  required List<(String, IconData, String, bool)> opciones,
  required ValueChanged<String> onSelected,
}) {
  final palette = context.palette;
  return PopupMenuButton<String>(
    tooltip: 'Acciones',
    icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
    color: palette.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    onSelected: (v) {
      // Sin esto, al cerrarse el menú y reconstruirse la card (la lista
      // completa viene de un `StreamBuilder` que reemite en cuanto la
      // acción escribe en Firestore), el foco caía por defecto en el
      // buscador de arriba y abría el teclado solo — visto en dispositivo
      // real al tocar "Habilitar usuario".
      FocusScope.of(context).unfocus();
      onSelected(v);
    },
    itemBuilder: (_) => [
      for (final (valor, icono, texto, peligro) in opciones)
        PopupMenuItem(
          value: valor,
          child: Row(
            children: [
              Icon(
                icono,
                size: 20,
                color: peligro ? AppColores.error : palette.textPrimary,
              ),
              const SizedBox(width: 12),
              Text(
                texto,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: peligro ? AppColores.error : palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
    ],
  );
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
      icono: Icons.block_rounded,
    );
    if (!ok) return;
    await onDeshabilitar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(
        context,
        titulo: 'Usuario deshabilitado',
        mensaje: nombre,
      );
    }
  }

  Future<void> _habilitar(BuildContext context, String nombre) async {
    await onHabilitar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(context, titulo: 'Usuario habilitado', mensaje: nombre);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = doc.data();
    final nombre = _nombreCompleto(data, 'Cliente');
    final contacto = _str(data, [
      'telefono',
      'correo',
      'email',
    ], 'Sin contacto');
    final foto = _str(data, ['foto', 'fotoUrl'], '');
    final deshabilitado = data['deshabilitado'] == true;

    return _Tarjeta(
      child: Row(
        children: [
          _Avatar(foto: foto, radio: 22, esConductor: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (deshabilitado) ...[
                      const SizedBox(width: 6),
                      const _BadgeDeshabilitado(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  contacto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          _menuAcciones(
            context,
            opciones: [
              ('detalles', Icons.visibility_outlined, 'Ver detalles', false),
              if (deshabilitado)
                (
                  'habilitar',
                  Icons.check_circle_outline_rounded,
                  'Habilitar usuario',
                  false,
                )
              else
                ('deshabilitar', Icons.block_rounded, 'Deshabilitar', true),
            ],
            onSelected: (v) {
              if (v == 'detalles') _verDetalles(context, data);
              if (v == 'deshabilitar') _deshabilitar(context, nombre);
              if (v == 'habilitar') _habilitar(context, nombre);
            },
          ),
        ],
      ),
    );
  }
}

class _BadgeDeshabilitado extends StatelessWidget {
  const _BadgeDeshabilitado();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColores.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'Deshabilitado',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
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
        mensaje: '$nombre no solicitó la activación. ¿Activar de todas formas?',
        accion: 'Activar',
        icono: Icons.workspace_premium_outlined,
      );
      if (!ok) return;
      if (!context.mounted) return;
    }
    final dias = await mostrarDialogoDiasMembresia(context);
    if (dias == null) return;
    await onAprobar(uid: doc.id, dias: dias, nombre: nombre);

    if (context.mounted) {
      mostrarAvisoExito(
        context,
        titulo: 'Membresía activada',
        mensaje: '$nombre · $dias días',
      );
    }
  }

  Future<void> _revocar(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Revocar membresía',
      mensaje:
          'Se desactivará el servicio de $nombre. Tendrá que activar de nuevo.',
      accion: 'Revocar',
      peligro: true,
    );
    if (!ok) return;
    await onRevocar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(context, titulo: 'Membresía revocada', mensaje: nombre);
    }
  }

  Future<void> _quitarConductor(BuildContext context, String nombre) async {
    final ok = await mostrarConfirmacion(
      context,
      titulo: 'Quitar como conductor',
      mensaje: '$nombre volverá a ser cliente. Se desactiva su servicio.',
      accion: 'Quitar',
      peligro: true,
      icono: Icons.person_remove_outlined,
    );
    if (!ok) return;
    await onQuitar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(context, titulo: 'Pasó a cliente', mensaje: nombre);
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
      icono: Icons.block_rounded,
    );
    if (!ok) return;
    await onDeshabilitar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(
        context,
        titulo: 'Usuario deshabilitado',
        mensaje: nombre,
      );
    }
  }

  Future<void> _habilitar(BuildContext context, String nombre) async {
    await onHabilitar(doc.id);
    if (context.mounted) {
      mostrarAvisoExito(context, titulo: 'Usuario habilitado', mensaje: nombre);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final data = doc.data();
    final nombre = _nombreCompleto(data, 'Conductor');
    final placa = _str(data, ['placa'], '');
    final vehiculo = [
      placa.toUpperCase(),
      VehiculoValidator.descripcion(
        data['modeloVehiculo']?.toString(),
        data['colorVehiculo']?.toString(),
      ),
    ].where((p) => p.isNotEmpty).join(' · ');
    final foto = _str(data, ['foto', 'fotoUrl'], '');
    final activa = membresiaActiva(data);
    final pidio = data['solicitudConductor'] == true;
    final dias = data['membresiaDias'];
    final vence = data['membresiaVence'];
    final deshabilitado = data['deshabilitado'] == true;

    Widget estado(
      Color color,
      IconData icono,
      String titulo,
      String? detalle,
    ) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                if (detalle != null)
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return _Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(foto: foto, radio: 22, esConductor: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (deshabilitado) ...[
                          const SizedBox(width: 6),
                          const _BadgeDeshabilitado(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehiculo.isEmpty ? 'Sin datos del vehículo' : vehiculo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _menuAcciones(
                context,
                opciones: [
                  (
                    'detalles',
                    Icons.visibility_outlined,
                    'Ver detalles',
                    false,
                  ),
                  if (activa)
                    (
                      'revocar',
                      Icons.remove_moderator_outlined,
                      'Revocar membresía',
                      true,
                    ),
                  (
                    'quitar',
                    Icons.person_remove_outlined,
                    'Quitar como conductor',
                    true,
                  ),
                  if (deshabilitado)
                    (
                      'habilitar',
                      Icons.check_circle_outline_rounded,
                      'Habilitar usuario',
                      false,
                    )
                  else
                    ('deshabilitar', Icons.block_rounded, 'Deshabilitar', true),
                ],
                onSelected: (v) {
                  if (v == 'detalles') _verDetalles(context, data);
                  if (v == 'revocar') _revocar(context, nombre);
                  if (v == 'quitar') _quitarConductor(context, nombre);
                  if (v == 'deshabilitar') _deshabilitar(context, nombre);
                  if (v == 'habilitar') _habilitar(context, nombre);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: activa
                ? estado(
                    AppColores.success,
                    Icons.workspace_premium_rounded,
                    'Membresía activa',
                    dias != null
                        ? '$dias días${vence is Timestamp ? ' · vence ${_fechaCorta(vence)}' : ''}'
                        : null,
                  )
                : pidio
                ? Column(
                    children: [
                      estado(
                        AppColores.warning,
                        Icons.notifications_active_rounded,
                        'Quiere activar el servicio',
                        'Revisa el comprobante antes de aprobar.',
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColores.success,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            'Aprobar y activar membresía',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          onPressed: () => _aprobar(context, nombre),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: palette.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Registrado · sin solicitud de activación',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _aprobar(context, nombre),
                        style: TextButton.styleFrom(
                          foregroundColor: acentoMarca(context),
                        ),
                        child: const Text(
                          'Activar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
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
  int _sugerencias = 0;

  StreamSubscription<QuerySnapshot>? _chatsSub;
  StreamSubscription<QuerySnapshot>? _reportesSub;
  StreamSubscription<int>? _sugerenciasSub;

  int get _total => _chats + _reportes + _sugerencias;

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

    _sugerenciasSub = SugerenciasService.instance.watchNoVistasCount().listen(
      (n) {
        if (!mounted) return;
        setState(() => _sugerencias = n);
      },
      onError: (e, st) =>
          ErrorReporter.report(e, st, reason: 'AdminBellIcon: sugerencias'),
    );
  }

  @override
  void dispose() {
    _chatsSub?.cancel();
    _reportesSub?.cancel();
    _sugerenciasSub?.cancel();
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
      tooltip: 'Notificaciones — Reportes, Mensajes y Sugerencias',
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
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
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
