import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Piezas comunes de las pantallas de cuenta (perfil, información del
/// perfil, configuración, registro de conductor): AppBar del color del
/// fondo, grupos de opciones y filas. Todo lee `context.palette`, así que
/// funciona igual en claro y oscuro.

/// Naranja legible como TEXTO de acento: el oscurecido en claro (el naranja
/// principal no se lee sobre blanco) y el principal en oscuro. Los íconos de
/// acento usan directamente `AppColores.primary` en ambos modos.
Color acentoMarca(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppColores.primary
    : AppColores.primaryDark;

/// AppBar sin color de marca: fondo y barra de estado del color del fondo
/// del tema. El `statusBarColor` va explícito porque con `null` Android
/// conserva el que haya dejado otra pantalla (el naranja de marca).
AppBar appBarNeutra(
  BuildContext context, {
  required String titulo,
  bool automaticallyImplyLeading = true,
  Widget? leading,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  final palette = context.palette;
  final esOscuro = Theme.of(context).brightness == Brightness.dark;
  return AppBar(
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    backgroundColor: palette.background,
    foregroundColor: palette.textPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    systemOverlayStyle: SystemUiOverlayStyle(
      statusBarColor: palette.background,
      statusBarIconBrightness: esOscuro ? Brightness.light : Brightness.dark,
      statusBarBrightness: esOscuro ? Brightness.dark : Brightness.light,
    ),
    title: Text(
      titulo,
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: palette.textPrimary,
      ),
    ),
    actions: actions,
    bottom: bottom,
  );
}

/// Pestañas con el estilo de la app: indicador ámbar, texto del tema.
TabBar tabBarNeutra(BuildContext context, {required List<Widget> tabs}) {
  final palette = context.palette;
  return TabBar(
    tabs: tabs,
    indicatorColor: AppColores.primary,
    indicatorWeight: 3,
    indicatorSize: TabBarIndicatorSize.label,
    labelColor: palette.textPrimary,
    unselectedLabelColor: palette.textSecondary,
    labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
    unselectedLabelStyle: const TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
    ),
    dividerColor: palette.borderSubtle,
  );
}

/// Grupo de filas con título en versalitas y separadores finos.
class SeccionAgrupada extends StatelessWidget {
  const SeccionAgrupada({
    super.key,
    required this.titulo,
    required this.children,
  });

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            titulo.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: palette.textSecondary,
            ),
          ),
        ),
        Material(
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: palette.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    color: palette.divider,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila tocable: ícono opcional, título, subtítulo y chevron (o [trailing]).
class FilaOpcion extends StatelessWidget {
  const FilaOpcion({
    super.key,
    required this.titulo,
    this.icono,
    this.subtitulo,
    this.onTap,
    this.trailing,
    this.destacado = false,
    this.peligro = false,
  });

  final String titulo;
  final IconData? icono;
  final String? subtitulo;
  final VoidCallback? onTap;

  /// Reemplaza al chevron (p.ej. un valor actual o un spinner).
  final Widget? trailing;

  /// Acento de marca en el ícono (acción que se quiere promover).
  final bool destacado;

  /// Acción destructiva (cerrar sesión, eliminar cuenta): todo en rojo.
  final bool peligro;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final habilitado = onTap != null;
    final colorTitulo = peligro ? AppColores.error : palette.textPrimary;
    final colorIcono = peligro
        ? AppColores.error
        : destacado
        ? AppColores.primary
        : palette.textPrimary;
    final fondoIcono = peligro
        ? AppColores.error.withValues(alpha: 0.12)
        : destacado
        ? AppColores.primary.withValues(alpha: 0.18)
        : palette.grey100;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: habilitado || trailing != null ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              if (icono != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fondoIcono,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icono, size: 21, color: colorIcono),
                ),
                const SizedBox(width: 14),
              ] else
                const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colorTitulo,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  (habilitado
                      ? Icon(
                          Icons.chevron_right_rounded,
                          color: palette.textSecondary.withValues(alpha: 0.8),
                        )
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila de solo lectura: etiqueta pequeña arriba y valor debajo.
class FilaDato extends StatelessWidget {
  const FilaDato({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icono, size: 21, color: palette.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
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

/// Botón principal fijo abajo (ámbar de marca, texto negro), con el borde
/// superior y el margen del área segura.
class BarraAccionInferior extends StatelessWidget {
  const BarraAccionInferior({
    super.key,
    required this.texto,
    required this.onPressed,
    this.icono,
    this.cargando = false,
  });

  final String texto;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        // `Align` con `heightFactor: 1` y no `Center`: en
        // `bottomNavigationBar` las restricciones de alto son sueltas y
        // `Center` se estiraba a toda la pantalla, tapando el cuerpo.
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: cargando ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColores.buttonPrimary,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppColores.buttonPrimary.withValues(
                    alpha: 0.6,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: cargando
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.black,
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icono != null) ...[
                              Icon(icono, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              texto,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
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
  }
}

/// Ícono de marca en círculo + título + descripción, centrados.
class EncabezadoIcono extends StatelessWidget {
  const EncabezadoIcono({
    super.key,
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColores.primary.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icono, size: 36, color: AppColores.primary),
        ),
        const SizedBox(height: 14),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          descripcion,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Aviso de éxito flotante abajo (no modal): tarjeta con check, título y
/// mensaje que se retira sola a los [duracion]. Usa el `ScaffoldMessenger`
/// de la app, así que sobrevive a un `Navigator.pop` inmediato: se puede
/// mostrar y volver a la pantalla anterior en el mismo paso.
void mostrarAvisoExito(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  Duration duracion = const Duration(seconds: 2),
}) => _mostrarAviso(
  context,
  titulo: titulo,
  mensaje: mensaje,
  color: AppColores.success,
  icono: Icons.check_rounded,
  duracion: duracion,
);

/// Igual que [mostrarAvisoExito] pero de advertencia (ámbar): algo impidió
/// la acción y el usuario puede resolverlo. [accion]/[onAccion] agregan un
/// botón a la derecha (ej. "Activar").
void mostrarAvisoAdvertencia(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String? accion,
  VoidCallback? onAccion,
  Duration duracion = const Duration(seconds: 4),
}) => _mostrarAviso(
  context,
  titulo: titulo,
  mensaje: mensaje,
  color: AppColores.warning,
  icono: Icons.priority_high_rounded,
  duracion: duracion,
  accion: accion,
  onAccion: onAccion,
);

void _mostrarAviso(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required Color color,
  required IconData icono,
  required Duration duracion,
  String? accion,
  VoidCallback? onAccion,
}) {
  final palette = context.palette;
  final messenger = ScaffoldMessenger.of(context);
  final acento = acentoMarca(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duracion,
        elevation: 6,
        backgroundColor: palette.surface,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: 0.45)),
        ),
        content: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    mensaje,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (accion != null && onAccion != null)
              TextButton(
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  onAccion();
                },
                style: TextButton.styleFrom(
                  foregroundColor: acento,
                  iconColor: AppColores.primary,
                ),
                child: Text(
                  accion,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
}
