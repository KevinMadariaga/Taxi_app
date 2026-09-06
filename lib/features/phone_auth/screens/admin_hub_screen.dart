import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/core/helpers/responsive_helper.dart';
import 'package:taxi_app/core/services/reportes_service.dart';
import 'package:taxi_app/core/services/soporte_chat_service.dart';
import 'package:taxi_app/core/services/sugerencias_service.dart';

import 'soporte_chat_detalle_admin_screen.dart';

/// Ancho máximo del contenido en tablet/desktop, centrado — mismo criterio
/// que `AdminHomeScreen`, para que el panel se vea coherente en toda la app
/// y no se estire ilegible en pantallas anchas.
const double _kContentMaxWidth = 640;

class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  int _reportes = 0;
  int _mensajes = 0;
  int _sugerencias = 0;

  StreamSubscription<int>? _reportesSub;
  StreamSubscription<int>? _mensajesSub;
  StreamSubscription<int>? _sugerenciasSub;

  @override
  void initState() {
    super.initState();

    _reportesSub = ReportesService.instance.watchNoVistosCount().listen(
      (n) => setState(() => _reportes = n),
    );

    _mensajesSub = SoporteChatService()
        .watchChatsConMensajesNuevosCount()
        .listen((n) => setState(() => _mensajes = n));

    _sugerenciasSub = SugerenciasService.instance.watchNoVistasCount().listen(
      (n) => setState(() => _sugerencias = n),
    );
  }

  @override
  void dispose() {
    _reportesSub?.cancel();
    _mensajesSub?.cancel();
    _sugerenciasSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resp = ResponsiveHelper.getResponsiveData(context);
    final isCompact = resp.deviceType == DeviceType.mobile;

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(
          backgroundColor: AppColores.primary,
          foregroundColor: AppColores.textWhite,
          elevation: 0,
          title: Text(
            'Gestión',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: ResponsiveHelper.sp(context, isCompact ? 18 : 20),
            ),
          ),
          bottom: PreferredSize(
            // `hp(context, 6.2)` puro rompía en landscape de iPhone: con la
            // altura de pantalla ahí (~375-430dp), 6.2% da ~23-27px — no
            // entra un `TabBar` (necesita ~46-48px) y encima ese ancho
            // clasifica como "no compacto", pidiendo fuente más grande
            // todavía. `clamp` fija un piso/techo absolutos en vez de
            // depender solo del porcentaje.
            preferredSize: Size.fromHeight(
              ResponsiveHelper.hp(context, 6.2).clamp(48.0, 64.0),
            ),
            child: Container(
              color: AppColores.primary,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
                child: TabBar(
                  labelColor: AppColores.textWhite,
                  unselectedLabelColor: AppColores.textWhite.withValues(
                    alpha: 0.6,
                  ),
                  indicatorColor: AppColores.textWhite,
                  indicatorWeight: 3,
                  labelPadding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.wp(context, isCompact ? 1 : 3),
                  ),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: ResponsiveHelper.sp(
                      context,
                      isCompact ? 12.5 : 14,
                    ),
                  ),
                  unselectedLabelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: ResponsiveHelper.sp(
                      context,
                      isCompact ? 12.5 : 14,
                    ),
                  ),
                  tabs: [
                    _BadgeTab(label: 'Reportes', count: _reportes),
                    _BadgeTab(label: 'Mensajes', count: _mensajes),
                    _BadgeTab(label: 'Sugerencias', count: _sugerencias),
                  ],
                ),
              ),
            ),
          ),
        ),
        // `SafeArea(top: false)`: sin esto, en dispositivos con navegación
        // por gestos las últimas tarjetas de cada lista quedaban detrás de
        // la barra del sistema y no había forma de scrollear lo suficiente
        // para revisarlas del todo — mismo problema, mismo fix, que el de
        // los bottom sheets de detalle (`_mostrarDetalleSheet`) más abajo en
        // este archivo. `top: false` porque el `AppBar` ya cubre esa zona.
        body: const SafeArea(
          top: false,
          child: TabBarView(
            children: [_TabReportes(), _TabMensajes(), _TabSugerencias()],
          ),
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
    // `FittedBox` en vez de un `Row` suelto: con 3 tabs fijas (no scrollable)
    // y "Sugerencias" siendo la más larga, el badge de conteo sumado al
    // texto podía desbordar el ancho disponible del tab en pantallas
    // angostas — visto en dispositivo real. Achicar todo el contenido en
    // conjunto en vez de truncar el texto evita que el badge quede cortado.
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
      ),
    );
  }
}

/// Centra el contenido y lo acota en tablet/desktop — envoltorio común a las
/// tres pestañas para que el ancho de lectura no se estire en pantallas
/// grandes, igual que el resto del panel admin.
class _ContenidoCentrado extends StatelessWidget {
  const _ContenidoCentrado({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
        child: child,
      ),
    );
  }
}

/// Estado vacío moderno: ícono en círculo suave + texto, en vez de un
/// `Text` centrado a secas.
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.wp(context, 8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: ResponsiveHelper.wp(context, 18).clamp(64.0, 96.0),
              height: ResponsiveHelper.wp(context, 18).clamp(64.0, 96.0),
              decoration: BoxDecoration(
                color: context.palette.grey100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icono,
                size: ResponsiveHelper.wp(context, 8).clamp(28.0, 40.0),
                color: context.palette.grey400,
              ),
            ),
            SizedBox(height: ResponsiveHelper.hp(context, 1.6)),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: ResponsiveHelper.sp(context, 14),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta moderna común a las tres pestañas: avatar redondo, título,
/// subtítulo, columna trailing y punto de "no leído". Reemplaza al
/// `ListTile` con `tileColor` plano por un `Card` con sombra suave, más
/// acorde al resto del panel (`_ConductorCard`/`_ClienteCard` del admin).
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.leadingIcon,
    required this.leadingBg,
    required this.leadingColor,
    required this.title,
    this.subtitle,
    this.trailingTop,
    this.noLeido = false,
    this.accentColor = AppColores.primary,
    required this.onTap,
  });

  final IconData leadingIcon;
  final Color leadingBg;
  final Color leadingColor;
  final Widget title;
  final Widget? subtitle;
  final String? trailingTop;
  final bool noLeido;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarSize = ResponsiveHelper.wp(context, 11).clamp(40.0, 52.0);
    return Card(
      margin: EdgeInsets.zero,
      elevation: noLeido ? 1.5 : 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: noLeido
          ? accentColor.withValues(alpha: 0.05)
          : context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: noLeido
              ? accentColor.withValues(alpha: 0.25)
              : context.palette.borderSubtle,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.wp(context, 3.5),
            vertical: ResponsiveHelper.hp(context, 1.3),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: leadingBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  leadingIcon,
                  color: leadingColor,
                  size: avatarSize * 0.46,
                ),
              ),
              SizedBox(width: ResponsiveHelper.wp(context, 3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      SizedBox(height: ResponsiveHelper.hp(context, 0.3)),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              SizedBox(width: ResponsiveHelper.wp(context, 2)),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (trailingTop != null)
                    Text(
                      trailingTop!,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.sp(context, 11),
                        color: context.palette.textSecondary,
                      ),
                    ),
                  if (noLeido)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenedor común de los bottom sheets de detalle: acota el ancho en
/// pantallas grandes (tablet/desktop) para que no se estiren de punta a
/// punta, igual que el resto del contenido del panel.
Future<T?> _mostrarDetalleSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  // `constraints` solo traía `maxWidth`: sin un `maxHeight` explícito, un
  // mensaje largo (sugerencia o comentario de reporte) hacía crecer la
  // `Column` del contenido más allá de lo que entra en pantalla y, al no
  // estar envuelta en algo desplazable, el final quedaba cortado — el sheet
  // "no se abría por completo", visto en dispositivo real. Ahora se acota
  // la altura al 85% de la pantalla y el contenido entero se vuelve
  // desplazable dentro de ese límite.
  //
  // `SafeArea` explícito alrededor del contenido (no solo `useSafeArea` de
  // la ruta, que resuelve el status bar de arriba en diálogos full-screen
  // pero no garantiza el inset inferior de la barra de navegación/gesture
  // bar de Android una vez que el contenido queda envuelto en el
  // `SingleChildScrollView` de arriba): sin esto, con un mensaje CORTO el
  // sheet se ajusta a su alto mínimo y esa última línea de texto termina
  // tapada por la barra de navegación del sistema — visto en dispositivo
  // real (Android, gesture nav).
  final maxHeight = MediaQuery.of(context).size.height * 0.85;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    constraints: BoxConstraints(
      maxWidth: _kContentMaxWidth,
      maxHeight: maxHeight,
    ),
    builder: (ctx) =>
        SafeArea(top: false, child: SingleChildScrollView(child: builder(ctx))),
  );
}

// ─── TAB REPORTES ────────────────────────────────────────────────────────────

class _TabReportes extends StatelessWidget {
  const _TabReportes();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ReportesService.instance.watchReportes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const _EstadoVacio(
            icono: Icons.flag_outlined,
            texto: 'Sin reportes registrados.',
          );
        }

        return _ContenidoCentrado(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.wp(context, 4),
              vertical: ResponsiveHelper.hp(context, 2),
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) =>
                SizedBox(height: ResponsiveHelper.hp(context, 1)),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final conductor = (data['conductor'] ?? 'Conductor desconocido')
                  .toString();
              final motivos =
                  (data['motivos'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final comentario = (data['comentario'] ?? '').toString();
              final ts = data['createdAt'] as Timestamp?;
              final fecha = ts != null
                  ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                  : '';
              final visto = data['visto'] as bool? ?? false;

              return _ItemCard(
                leadingIcon: Icons.flag_rounded,
                leadingBg: visto
                    ? context.palette.grey200
                    : AppColores.error.withValues(alpha: 0.12),
                leadingColor: visto
                    ? context.palette.textSecondary
                    : AppColores.error,
                accentColor: AppColores.error,
                noLeido: !visto,
                trailingTop: fecha,
                title: Text(
                  'Conductor: $conductor',
                  style: TextStyle(
                    fontWeight: visto ? FontWeight.w500 : FontWeight.w700,
                    fontSize: ResponsiveHelper.sp(context, 14.5),
                  ),
                ),
                subtitle: motivos.isEmpty && comentario.isEmpty
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (motivos.isNotEmpty)
                            Text(
                              motivos.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: ResponsiveHelper.sp(context, 12),
                                color: context.palette.textSecondary,
                              ),
                            ),
                          if (comentario.isNotEmpty)
                            Text(
                              comentario,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: ResponsiveHelper.sp(context, 12),
                              ),
                            ),
                        ],
                      ),
                onTap: () async {
                  if (!visto) {
                    await ReportesService.instance.marcarVisto(docs[index].id);
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
          ),
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
    _mostrarDetalleSheet<void>(
      context,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.wp(context, 5),
          20,
          ResponsiveHelper.wp(context, 5),
          32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: AppColores.error),
                const SizedBox(width: 8),
                Text(
                  'Detalle del reporte',
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 18),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  fecha,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detalleRow(context, 'Conductor', conductor),
            const SizedBox(height: 8),
            _detalleRow(context, 'Motivos', motivos.join(', ')),
            if (comentario.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detalleRow(context, 'Comentario', comentario),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detalleRow(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: ResponsiveHelper.sp(context, 15)),
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
          return const _EstadoVacio(
            icono: Icons.chat_bubble_outline_rounded,
            texto: 'Sin chats de soporte activos.',
          );
        }

        return _ContenidoCentrado(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.wp(context, 4),
              vertical: ResponsiveHelper.hp(context, 2),
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) =>
                SizedBox(height: ResponsiveHelper.hp(context, 1)),
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

              return _ItemCard(
                leadingIcon: userType == 'conductor'
                    ? Icons.local_taxi
                    : Icons.person,
                leadingBg: hayNuevos
                    ? AppColores.primary
                    : context.palette.grey200,
                leadingColor: hayNuevos
                    ? context.palette.textPrimary
                    : context.palette.textSecondary,
                noLeido: hayNuevos,
                trailingTop: hora,
                title: Text(
                  userName,
                  style: TextStyle(
                    fontWeight: hayNuevos ? FontWeight.w700 : FontWeight.w500,
                    fontSize: ResponsiveHelper.sp(context, 14.5),
                  ),
                ),
                subtitle: Text(
                  ultimoMensaje,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 12.5),
                    color: hayNuevos
                        ? context.palette.textPrimary
                        : context.palette.textSecondary,
                    fontWeight: hayNuevos ? FontWeight.w600 : FontWeight.normal,
                  ),
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
          ),
        );
      },
    );
  }
}

// ─── TAB SUGERENCIAS ─────────────────────────────────────────────────────────

class _TabSugerencias extends StatelessWidget {
  const _TabSugerencias();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SugerenciasService.instance.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const _EstadoVacio(
            icono: Icons.lightbulb_outline_rounded,
            texto: 'Sin sugerencias aún.',
          );
        }

        return _ContenidoCentrado(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.wp(context, 4),
              vertical: ResponsiveHelper.hp(context, 2),
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) =>
                SizedBox(height: ResponsiveHelper.hp(context, 1)),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final tipo = (data['tipo'] ?? 'cliente').toString();
              final mensaje = (data['mensaje'] ?? '').toString();
              final estrellas = (data['estrellas'] as num?)?.toInt() ?? 0;
              final visto = data['visto'] as bool? ?? false;
              final ts = data['creadoEn'] as Timestamp?;
              final fecha = ts != null
                  ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                  : '';
              final esConductor = tipo == 'conductor';

              return _ItemCard(
                leadingIcon: esConductor ? Icons.local_taxi : Icons.person,
                leadingBg: visto
                    ? context.palette.grey200
                    : AppColores.primary.withValues(alpha: 0.15),
                leadingColor: visto
                    ? context.palette.textSecondary
                    : context.palette.textPrimary,
                noLeido: !visto,
                trailingTop: fecha,
                title: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: esConductor
                            ? AppColores.primary.withValues(alpha: 0.12)
                            : Colors.blue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        esConductor ? 'Conductor' : 'Cliente',
                        style: TextStyle(
                          fontSize: ResponsiveHelper.sp(context, 11),
                          fontWeight: FontWeight.w700,
                          color: esConductor
                              ? const Color(0xFF7A6000)
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    if (estrellas > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          estrellas,
                          (_) => const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFFFC107),
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: mensaje.isEmpty
                    ? null
                    : Text(
                        mensaje,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: ResponsiveHelper.sp(context, 12.5),
                          color: visto
                              ? context.palette.textSecondary
                              : context.palette.textPrimary,
                          fontWeight: visto
                              ? FontWeight.normal
                              : FontWeight.w500,
                        ),
                      ),
                onTap: () async {
                  if (!visto) {
                    await SugerenciasService.instance.marcarVisto(
                      docs[index].id,
                    );
                  }
                  if (context.mounted && mensaje.isNotEmpty) {
                    _mostrarDetalleSugerencia(
                      context,
                      tipo: tipo,
                      mensaje: mensaje,
                      estrellas: estrellas,
                      fecha: fecha,
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  void _mostrarDetalleSugerencia(
    BuildContext context, {
    required String tipo,
    required String mensaje,
    required int estrellas,
    required String fecha,
  }) {
    _mostrarDetalleSheet<void>(
      context,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.wp(context, 5),
          20,
          ResponsiveHelper.wp(context, 5),
          32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.palette.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: AppColores.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sugerencia',
                  style: TextStyle(
                    fontSize: ResponsiveHelper.sp(context, 18),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  fecha,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tipo == 'conductor' ? 'Conductor' : 'Cliente',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.palette.textSecondary,
              ),
            ),
            if (estrellas > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  estrellas,
                  (_) => const Icon(
                    Icons.star_rounded,
                    size: 20,
                    color: Color(0xFFFFC107),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              mensaje,
              style: TextStyle(fontSize: ResponsiveHelper.sp(context, 15)),
            ),
          ],
        ),
      ),
    );
  }
}
