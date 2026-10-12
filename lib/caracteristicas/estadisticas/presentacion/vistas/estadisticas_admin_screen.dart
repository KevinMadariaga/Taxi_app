import 'package:flutter/material.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

import '../../datos/repositorios/estadisticas_repository_impl.dart';
import '../../dominio/entidades/estadistica_dia.dart';
import '../../dominio/repositorios/estadisticas_repository.dart';
import '../widgets/graficas.dart';

const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _fechaCorta(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Sección "Estadísticas" del panel admin: cómo va el flujo de solicitudes.
/// Indicadores del día elegido (hoy por defecto), resultados por día en
/// barras apiladas, solicitudes por hora y la tabla con los números.
class EstadisticasAdminScreen extends StatefulWidget {
  const EstadisticasAdminScreen({
    super.key,
    EstadisticasRepository? repositorio,
  }) : _repositorio = repositorio;

  final EstadisticasRepository? _repositorio;

  @override
  State<EstadisticasAdminScreen> createState() =>
      _EstadisticasAdminScreenState();
}

class _EstadisticasAdminScreenState extends State<EstadisticasAdminScreen> {
  late final EstadisticasRepository _repo =
      widget._repositorio ?? EstadisticasRepositoryImpl();
  int _rango = 7;
  late Stream<List<EstadisticaDia>> _datos = _repo.watchUltimosDias(_rango);

  /// Índice del día elegido en la lista; `null` = hoy (el último).
  int? _seleccion;

  void _cambiarRango(int dias) => setState(() {
    _rango = dias;
    _seleccion = null;
    _datos = _repo.watchUltimosDias(dias);
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: appBarNeutra(context, titulo: 'Estadísticas'),
      body: StreamBuilder<List<EstadisticaDia>>(
        stream: _datos,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Text('No se pudieron cargar las estadísticas.'),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final dias = snap.data!;
          final i = (_seleccion ?? dias.length - 1).clamp(0, dias.length - 1);
          final dia = dias[i];
          final esHoy = i == dias.length - 1;
          final sinDatos = dias.every((d) => d.creadas == 0);

          return LayoutBuilder(
            builder: (context, c) {
              final ancho = c.maxWidth >= 900;
              final graficaDias = _Tarjeta(
                titulo: 'Resultado por día',
                subtitulo: 'Toca un día para ver su detalle',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GraficaResultadosPorDia(
                      dias: dias,
                      seleccionado: i,
                      onSeleccionar: (k) => setState(() => _seleccion = k),
                    ),
                    const SizedBox(height: 12),
                    const Leyenda(items: ColoresResultado.leyenda),
                  ],
                ),
              );
              final graficaHoras = _Tarjeta(
                titulo: 'Solicitudes por hora',
                subtitulo: esHoy ? 'Hoy' : _fechaCorta(dia.dia),
                child: GraficaPorHora(dia: dia),
              );
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SelectorRango(valor: _rango, onCambio: _cambiarRango),
                        const SizedBox(height: 14),
                        if (sinDatos) ...[
                          const _AvisoSinDatos(),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          esHoy ? 'Hoy' : _fechaCorta(dia.dia),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Indicadores(dia: dia),
                        const SizedBox(height: 16),
                        if (ancho)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: graficaDias),
                                const SizedBox(width: 16),
                                Expanded(child: graficaHoras),
                              ],
                            ),
                          )
                        else ...[
                          graficaDias,
                          const SizedBox(height: 16),
                          graficaHoras,
                        ],
                        const SizedBox(height: 16),
                        _Tarjeta(
                          titulo: 'Últimos $_rango días',
                          child: _Tabla(dias: dias),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SelectorRango extends StatelessWidget {
  const _SelectorRango({required this.valor, required this.onCambio});

  final int valor;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final d in [7, 30])
          ChipSeleccion(
            texto: 'Últimos $d días',
            seleccionado: valor == d,
            onSeleccionar: () => onCambio(d),
          ),
      ],
    );
  }
}

class _AvisoSinDatos extends StatelessWidget {
  const _AvisoSinDatos();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: acentoMarca(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Todavía no hay solicitudes en este periodo. Las estadísticas '
              'se cuentan desde que se activó este panel.',
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Los números del día en tarjetas grandes: 2 columnas en teléfono, 3 en
/// tablet y 5 en pantallas anchas.
class _Indicadores extends StatelessWidget {
  const _Indicadores({required this.dia});

  final EstadisticaDia dia;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.receipt_long_rounded, 'Creadas', '${dia.creadas}', null),
      (
        Icons.person_rounded,
        'Usuarios que pidieron',
        '${dia.clientesUnicos}',
        null,
      ),
      (
        Icons.check_circle_rounded,
        'Completadas',
        '${dia.completadas}',
        ColoresResultado.completadas,
      ),
      (
        Icons.cancel_rounded,
        'Canceladas',
        '${dia.canceladas}',
        ColoresResultado.canceladas,
      ),
      (
        Icons.percent_rounded,
        'Tasa de completado',
        '${(dia.tasaCompletado * 100).round()}%',
        null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = c.maxWidth < 600
            ? 2
            : c.maxWidth < 1000
            ? 3
            : 5;
        const gap = 10.0;
        final ancho = (c.maxWidth - gap * (columnas - 1)) / columnas;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (icono, titulo, valor, color) in items)
              SizedBox(
                width: ancho,
                child: _Indicador(
                  icono: icono,
                  titulo: titulo,
                  valor: valor,
                  color: color,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.color,
  });

  final IconData icono;
  final String titulo;
  final String valor;

  /// El del resultado (completadas/canceladas); si no, el acento de marca.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final c = color ?? acentoMarca(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: c, size: 22),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.titulo, required this.child, this.subtitulo});

  final String titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.textPrimary,
            ),
          ),
          if (subtitulo != null)
            Text(
              subtitulo!,
              style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
            ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Los números en tabla (lo más nuevo arriba), con totales del periodo:
/// la lectura exacta que no depende de los colores de la gráfica.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.dias});

  final List<EstadisticaDia> dias;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    int suma(int Function(EstadisticaDia) f) =>
        dias.fold(0, (s, d) => s + f(d));
    final estiloTotal = TextStyle(
      fontWeight: FontWeight.w800,
      color: palette.textPrimary,
    );
    DataRow fila(List<String> celdas, {TextStyle? estilo}) => DataRow(
      cells: [for (final t in celdas) DataCell(Text(t, style: estilo))],
    );
    return SingleChildScrollView(
      // En teléfono la tabla es más ancha que la pantalla: se desplaza de
      // lado en vez de apretar las columnas.
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: palette.textSecondary,
        ),
        dataTextStyle: TextStyle(color: palette.textPrimary),
        columnSpacing: 20,
        horizontalMargin: 4,
        columns: const [
          DataColumn(label: Text('Día')),
          DataColumn(label: Text('Creadas'), numeric: true),
          DataColumn(label: Text('Completadas'), numeric: true),
          DataColumn(label: Text('Canceladas'), numeric: true),
          DataColumn(label: Text('Sin respuesta'), numeric: true),
          DataColumn(label: Text('Usuarios'), numeric: true),
        ],
        rows: [
          fila([
            'Total',
            '${suma((d) => d.creadas)}',
            '${suma((d) => d.completadas)}',
            '${suma((d) => d.canceladas)}',
            '${suma((d) => d.sinRespuesta)}',
            '—',
          ], estilo: estiloTotal),
          for (final d in dias.reversed)
            fila([
              _fechaCorta(d.dia),
              '${d.creadas}',
              '${d.completadas}',
              '${d.canceladas}',
              '${d.sinRespuesta}',
              '${d.clientesUnicos}',
            ]),
        ],
      ),
    );
  }
}
