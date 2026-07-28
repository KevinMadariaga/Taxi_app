import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:taxi_app/data/solicitud_repository.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/historial_detalle_conductor_viewmodel.dart';

const Color _amberDark = Color(0xFFB38F00);

class HistorialDetalleConductor extends StatefulWidget {
  final String conductorId;
  const HistorialDetalleConductor({super.key, required this.conductorId});

  @override
  State<HistorialDetalleConductor> createState() =>
      _HistorialDetalleConductorState();
}

class _HistorialDetalleConductorState extends State<HistorialDetalleConductor> {
  final HistorialDetalleConductorViewModel _viewModel =
      HistorialDetalleConductorViewModel();
  int selectedMonth = DateTime.now().month;
  String viewMode = 'dia'; // 'mes' | 'semana' | 'dia'
  int selectedWeekIndex = 0;
  DateTime selectedDate = DateTime.now();
  final List<String> monthNames = const [
    'Ene',
    'Feb',
    'Mar',
    'Abr',
    'May',
    'Jun',
    'Jul',
    'Ago',
    'Sep',
    'Oct',
    'Nov',
    'Dic',
  ];
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _solicitudesStream;

  @override
  void initState() {
    super.initState();
    _solicitudesStream = SolicitudRepositoryImpl().historialConductorStream(
      widget.conductorId,
    );
    initializeDateFormatting('es').then((_) {
      if (mounted) setState(() {});
    });
    final DateTime now = DateTime.now();
    final List<DateTime> weekStarts = _viewModel.computeWeekStarts(
      selectedMonth,
      now.year,
    );
    final int? currentWeekIndex = _viewModel.findWeekIndexForDate(
      weekStarts,
      now,
    );
    if (currentWeekIndex != null) {
      selectedWeekIndex = currentWeekIndex;
    }
  }

  void _showDayDetail(
    BuildContext context,
    DateTime date,
    double earnings,
    int count,
    NumberFormat integerFmt,
    NumberFormat twoDecFmt,
  ) {
    final String formatted = _viewModel.formatEarnings(
      earnings,
      integerFmt,
      twoDecFmt,
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          DateFormat('EEEE, d/MM/yyyy', 'es').format(date),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetalleLinea(
              icon: Icons.receipt_long_rounded,
              label: 'Solicitudes',
              value: '$count',
            ),
            const SizedBox(height: 10),
            _DetalleLinea(
              icon: Icons.payments_rounded,
              label: 'Ganado',
              value: '\$$formatted',
              color: AppColores.success,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        title: const Text(
          'Detalle de Ganancias',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColores.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _solicitudesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColores.primary),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];
          final now = DateTime.now();

          final aggregation = _viewModel.computeAggregation(
            docs: docs,
            selectedMonth: selectedMonth,
            selectedWeekIndex: selectedWeekIndex,
            selectedDate: selectedDate,
            viewMode: viewMode,
            now: now,
          );

          final headerDate = aggregation.headerDate;
          final todaysRequests = aggregation.todaysRequests;
          final formattedTodaysEarnings = aggregation.formattedTodaysEarnings;
          final weekStarts = aggregation.weekStarts;
          final weekCounts = aggregation.weekCounts;
          final integerFmt = aggregation.integerFmt;
          final twoDecFmt = aggregation.twoDecFmt;
          final selectedWeekDayEarnings = aggregation.selectedWeekDayEarnings;
          final selectedWeekDayCounts = aggregation.selectedWeekDayCounts;
          final hourlyEarnings = aggregation.hourlyEarnings;
          final hourlyRequests = aggregation.hourlyRequests;
          final statLabel1 = aggregation.statLabel1;
          final statCount1 = aggregation.statCount1;
          final statLabel2 = aggregation.statLabel2;
          final statEarnings = aggregation.statEarnings;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).padding.bottom + 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroGanancias(
                      subtitulo: 'Ganancias de $headerDate',
                      monto: '\$$formattedTodaysEarnings',
                      solicitudes: todaysRequests,
                    ),
                    const SizedBox(height: 20),
                    _SelectorModo(
                      modo: viewMode,
                      onChanged: (v) {
                        if (v == 'semana' && weekStarts.isNotEmpty) {
                          final int? todayWeekIndex = _viewModel
                              .findWeekIndexForDate(weekStarts, now);
                          setState(() {
                            viewMode = v;
                            if (todayWeekIndex != null) {
                              selectedWeekIndex = todayWeekIndex;
                            }
                          });
                        } else {
                          setState(() => viewMode = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    if (viewMode == 'mes')
                      _ChartCard(
                        titulo: 'Ganado por semanas',
                        child: _GraficoMes(
                          weekStarts: weekStarts,
                          weekCounts: weekCounts,
                          onTapSemana: (i) => setState(() {
                            viewMode = 'semana';
                            selectedWeekIndex = i;
                          }),
                        ),
                      )
                    else if (viewMode == 'semana' && weekStarts.isNotEmpty)
                      _ChartCard(
                        titulo: 'Solicitudes por día',
                        trailing: _SelectorSemana(
                          weekStarts: weekStarts,
                          selected: selectedWeekIndex,
                          onChanged: (v) =>
                              setState(() => selectedWeekIndex = v),
                        ),
                        child: _GraficoSemana(
                          weekStart: weekStarts[selectedWeekIndex],
                          dayCounts: selectedWeekDayCounts,
                          dayEarnings: selectedWeekDayEarnings,
                          onTapDia: (date, earn, cnt) => _showDayDetail(
                            context,
                            date,
                            earn,
                            cnt,
                            integerFmt,
                            twoDecFmt,
                          ),
                        ),
                      )
                    else if (viewMode == 'dia')
                      _ChartCard(
                        titulo: 'Rendimiento por turno',
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(
                            DateFormat('d/MM/yyyy').format(selectedDate),
                          ),
                        ),
                        child: _GraficoDia(
                          hourlyEarnings: hourlyEarnings,
                          hourlyRequests: hourlyRequests,
                        ),
                      ),
                    if (viewMode == 'mes') ...[
                      const SizedBox(height: 12),
                      _SelectorMes(
                        meses: monthNames,
                        selected: selectedMonth,
                        onChanged: (m) => setState(() {
                          selectedMonth = m;
                          selectedWeekIndex = 0;
                        }),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.receipt_long_rounded,
                            label: statLabel1,
                            value: statCount1.toString(),
                            color: _amberDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.payments_rounded,
                            label: statLabel2,
                            value: '\$$statEarnings',
                            color: AppColores.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _HeroGanancias extends StatelessWidget {
  const _HeroGanancias({
    required this.subtitulo,
    required this.monto,
    required this.solicitudes,
  });
  final String subtitulo;
  final String monto;
  final int solicitudes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColores.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColores.success.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColores.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              monto,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: AppColores.success,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.local_taxi_rounded,
                size: 18,
                color: AppColores.success,
              ),
              const SizedBox(width: 6),
              Text(
                '$solicitudes solicitudes hoy',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColores.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectorModo extends StatelessWidget {
  const _SelectorModo({required this.modo, required this.onChanged});
  final String modo;
  final ValueChanged<String> onChanged;

  static const _opciones = [
    ('dia', 'Día'),
    ('semana', 'Semana'),
    ('mes', 'Mes'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColores.grey200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _opciones.map((o) {
          final sel = modo == o.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? AppColores.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o.$2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: sel
                        ? AppColores.textPrimary
                        : AppColores.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.titulo, required this.child, this.trailing});
  final String titulo;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColores.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SelectorSemana extends StatelessWidget {
  const _SelectorSemana({
    required this.weekStarts,
    required this.selected,
    required this.onChanged,
  });
  final List<DateTime> weekStarts;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: selected,
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(fontSize: 11.5, color: AppColores.textPrimary),
        items: List.generate(weekStarts.length, (i) {
          final ws = weekStarts[i];
          final we = ws.add(const Duration(days: 6));
          return DropdownMenuItem(
            value: i,
            child: Text(
              'Sem.${i + 1} (${DateFormat('d/MM').format(ws)}-${DateFormat('d/MM').format(we)})',
            ),
          );
        }),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _SelectorMes extends StatelessWidget {
  const _SelectorMes({
    required this.meses,
    required this.selected,
    required this.onChanged,
  });
  final List<String> meses;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 12,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = i + 1;
          final sel = selected == m;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? AppColores.primary : AppColores.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel ? AppColores.primary : AppColores.borderSubtle,
                ),
              ),
              child: Text(
                meses[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : AppColores.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GraficoMes extends StatelessWidget {
  const _GraficoMes({
    required this.weekStarts,
    required this.weekCounts,
    required this.onTapSemana,
  });
  final List<DateTime> weekStarts;
  final List<int> weekCounts;
  final ValueChanged<int> onTapSemana;

  @override
  Widget build(BuildContext context) {
    final maxCount = weekCounts.fold<int>(0, (p, e) => e > p ? e : p);
    final maxDiv = maxCount == 0 ? 1.0 : maxCount.toDouble();

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(weekStarts.length, (i) {
          final count = weekCounts[i];
          double h = (count / maxDiv) * 110.0;
          if (count > 0 && h < 8) h = 8;
          final label = DateFormat('d/MM').format(weekStarts[i]);
          return Expanded(
            child: GestureDetector(
              onTap: () => onTapSemana(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    count.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 22,
                    height: h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD740), AppColores.primary],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _GraficoSemana extends StatelessWidget {
  const _GraficoSemana({
    required this.weekStart,
    required this.dayCounts,
    required this.dayEarnings,
    required this.onTapDia,
  });
  final DateTime weekStart;
  final List<int> dayCounts;
  final List<double> dayEarnings;
  final void Function(DateTime date, double earnings, int count) onTapDia;

  @override
  Widget build(BuildContext context) {
    final maxCount = dayCounts.fold<int>(0, (p, e) => e > p ? e : p);
    final maxDiv = maxCount == 0 ? 1.0 : maxCount.toDouble();

    return SizedBox(
      height: 178,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final count = dayCounts[i];
          final hasData = count > 0;
          double h = hasData ? 8.0 + (count / maxDiv) * 90.0 : 6.0;
          final dayDate = weekStart.add(Duration(days: i));
          final earn = dayEarnings.length > i ? dayEarnings[i] : 0.0;
          String dayLabel = DateFormat(
            'E',
            'es',
          ).format(dayDate).replaceAll('.', '');
          if (dayLabel.length > 3) dayLabel = dayLabel.substring(0, 3);
          dayLabel = dayLabel[0].toUpperCase() + dayLabel.substring(1);

          return Expanded(
            child: GestureDetector(
              onTap: () => onTapDia(dayDate, earn, count),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasData)
                    Text(
                      count.toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 26,
                    height: h,
                    decoration: BoxDecoration(
                      color: hasData ? AppColores.primary : AppColores.grey300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dayLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColores.textSecondary,
                    ),
                  ),
                  Text(
                    dayDate.day.toString(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColores.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _GraficoDia extends StatelessWidget {
  const _GraficoDia({
    required this.hourlyEarnings,
    required this.hourlyRequests,
  });
  final List<double> hourlyEarnings;
  final List<int> hourlyRequests;

  static const _turnos = [
    (
      name: 'Mañana',
      icon: Icons.wb_sunny_rounded,
      color: Color(0xFFFB8C00),
      start: 6,
      end: 12,
    ),
    (
      name: 'Tarde',
      icon: Icons.light_mode_rounded,
      color: AppColores.primary,
      start: 12,
      end: 18,
    ),
    (
      name: 'Noche',
      icon: Icons.nightlight_round,
      color: Color(0xFF1565C0),
      start: 18,
      end: 24,
    ),
    (
      name: 'Madrugada',
      icon: Icons.bedtime_rounded,
      color: Color(0xFF6A1B9A),
      start: 0,
      end: 6,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final total = hourlyEarnings.fold<double>(0, (p, e) => p + e);

    if (total == 0) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Sin actividad este día',
            style: TextStyle(color: AppColores.textSecondary),
          ),
        ),
      );
    }

    // Compute per-turno totals
    final turnoEarnings = <double>[];
    final turnoCounts = <int>[];
    for (final t in _turnos) {
      double e = 0;
      int c = 0;
      for (int h = t.start; h < t.end; h++) {
        e += hourlyEarnings[h];
        c += hourlyRequests[h];
      }
      turnoEarnings.add(e);
      turnoCounts.add(c);
    }

    final maxEarnings = turnoEarnings.fold<double>(0, (p, e) => e > p ? e : p);

    // Best individual hour
    int bestHour = 0;
    double bestVal = 0;
    for (int h = 0; h < 24; h++) {
      if (hourlyEarnings[h] > bestVal) {
        bestVal = hourlyEarnings[h];
        bestHour = h;
      }
    }

    final fmt = NumberFormat.decimalPattern('es');
    final fmtDec = NumberFormat('#,##0.00', 'es');
    String fmtEarnings(double v) =>
        v % 1 == 0 ? fmt.format(v.toInt()) : fmtDec.format(v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mejor hora badge
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColores.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                color: AppColores.primary,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                'Mejor hora: ${bestHour}:00 – ${(bestHour + 1) % 24}:00',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: AppColores.primary,
                ),
              ),
            ],
          ),
        ),
        // 2x2 turno grid
        Row(
          children: [
            Expanded(
              child: _buildTurnoCard(
                0,
                turnoEarnings,
                turnoCounts,
                maxEarnings,
                fmtEarnings,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTurnoCard(
                1,
                turnoEarnings,
                turnoCounts,
                maxEarnings,
                fmtEarnings,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildTurnoCard(
                2,
                turnoEarnings,
                turnoCounts,
                maxEarnings,
                fmtEarnings,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildTurnoCard(
                3,
                turnoEarnings,
                turnoCounts,
                maxEarnings,
                fmtEarnings,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTurnoCard(
    int i,
    List<double> earnings,
    List<int> counts,
    double maxEarnings,
    String Function(double) fmt,
  ) {
    final t = _turnos[i];
    final e = earnings[i];
    final c = counts[i];
    final ratio = maxEarnings == 0 ? 0.0 : (e / maxEarnings).clamp(0.0, 1.0);
    final isTop = e == maxEarnings && e > 0;
    final endLabel = t.end == 24 ? '0' : '${t.end}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTop ? t.color.withValues(alpha: 0.08) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTop ? t.color : Colors.grey.shade200,
          width: isTop ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(t.icon, color: t.color, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  t.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: t.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${t.start}h–${endLabel}h',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            '$c sol.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: c > 0 ? AppColores.textPrimary : AppColores.textSecondary,
            ),
          ),
          Text(
            '\$${fmt(e)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: e > 0 ? AppColores.success : AppColores.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: t.color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(t.color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColores.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColores.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetalleLinea extends StatelessWidget {
  const _DetalleLinea({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? AppColores.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: AppColores.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color ?? AppColores.textPrimary,
          ),
        ),
      ],
    );
  }
}
