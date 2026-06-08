import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

const Color _amberDark = Color(0xFFB38F00);

class HistorialDetalleConductor extends StatefulWidget {
  final String conductorId;
  const HistorialDetalleConductor({super.key, required this.conductorId});

  @override
  State<HistorialDetalleConductor> createState() =>
      _HistorialDetalleConductorState();
}

class _HistorialDetalleConductorState extends State<HistorialDetalleConductor> {
  int selectedMonth = DateTime.now().month;
  String viewMode = 'semana'; // 'mes' | 'semana' | 'dia'
  int selectedWeekIndex = 0;
  DateTime selectedDate = DateTime.now();
  final List<String> monthNames = const [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es').then((_) {
      if (mounted) setState(() {});
    });
    final DateTime now = DateTime.now();
    final int year = now.year;
    final DateTime firstDayOfMonth = DateTime(year, selectedMonth, 1);
    final DateTime lastDayOfMonth = (selectedMonth == 12)
        ? DateTime(year + 1, 1, 1).subtract(const Duration(days: 1))
        : DateTime(
            year,
            selectedMonth + 1,
            1,
          ).subtract(const Duration(days: 1));
    DateTime weekStart = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday - 1),
    );
    final List<DateTime> weekStarts = [];
    while (weekStart.isBefore(lastDayOfMonth) ||
        weekStart.isAtSameMomentAs(lastDayOfMonth)) {
      weekStarts.add(weekStart);
      weekStart = weekStart.add(const Duration(days: 7));
    }
    for (var i = 0; i < weekStarts.length; i++) {
      final ws = weekStarts[i];
      final we = ws.add(const Duration(days: 6));
      if (!now.isBefore(ws) && !now.isAfter(we)) {
        selectedWeekIndex = i;
        break;
      }
    }
  }

  double _valorDe(Map<String, dynamic> data) {
    final tarifa = data['tarifa'];
    if (tarifa is Map && tarifa['total'] != null) {
      final t = tarifa['total'];
      return t is num ? t.toDouble() : (double.tryParse(t.toString()) ?? 0.0);
    }
    if (data['valor'] != null) {
      final v = data['valor'];
      return v is num ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0);
    }
    return 0.0;
  }

  void _showDayDetail(
    BuildContext context,
    DateTime date,
    double earnings,
    int count,
    NumberFormat integerFmt,
    NumberFormat twoDecFmt,
  ) {
    final String formatted = (earnings % 1 == 0)
        ? integerFmt.format(earnings.toInt())
        : twoDecFmt.format(earnings);
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes')
            .where('conductor.id', isEqualTo: widget.conductorId)
            .snapshots(),
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

          // ── Agregación por día (para "hoy") ──────────────────────────────
          final Map<String, double> earningsByDay = {};
          final Map<String, int> countByDay = {};
          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final valor = _valorDe(data);
              final ts =
                  (data['completedAt'] ?? data['fecha de terminacion'])
                      as Timestamp?;
              final key = ts != null
                  ? ts.toDate().toLocal().toIso8601String().split('T').first
                  : 'Sin fecha';
              earningsByDay[key] = (earningsByDay[key] ?? 0.0) + valor;
              countByDay[key] = (countByDay[key] ?? 0) + 1;
            } catch (_) {}
          }

          final NumberFormat integerFmt = NumberFormat.decimalPattern('es');
          final NumberFormat twoDecFmt = NumberFormat('#,##0.00', 'es');

          final now = DateTime.now();
          final String weekdayAbbrevRaw = DateFormat('E', 'es').format(now);
          final String weekdayAbbrev = weekdayAbbrevRaw.replaceAll('.', '');
          final String weekdayCapital = weekdayAbbrev.isNotEmpty
              ? weekdayAbbrev[0].toUpperCase() + weekdayAbbrev.substring(1)
              : weekdayAbbrev;
          final String headerDate = '$weekdayCapital ${now.day} de hoy';
          final todayKey = now.toLocal().toIso8601String().split('T').first;
          final int todaysRequests = countByDay[todayKey] ?? 0;
          final double todaysEarnings = earningsByDay[todayKey] ?? 0.0;
          final String formattedTodaysEarnings = (todaysEarnings % 1 == 0)
              ? integerFmt.format(todaysEarnings.toInt())
              : twoDecFmt.format(todaysEarnings);

          final int year = now.year;
          final DateTime firstDayOfMonth = DateTime(year, selectedMonth, 1);
          final DateTime lastDayOfMonth = (selectedMonth == 12)
              ? DateTime(year + 1, 1, 1).subtract(const Duration(days: 1))
              : DateTime(
                  year,
                  selectedMonth + 1,
                  1,
                ).subtract(const Duration(days: 1));

          DateTime weekStart = firstDayOfMonth.subtract(
            Duration(days: firstDayOfMonth.weekday - 1),
          );
          final List<DateTime> weekStarts = [];
          while (weekStart.isBefore(lastDayOfMonth) ||
              weekStart.isAtSameMomentAs(lastDayOfMonth)) {
            weekStarts.add(weekStart);
            weekStart = weekStart.add(const Duration(days: 7));
          }

          final List<int> weekCounts = List.filled(weekStarts.length, 0);
          final List<double> weekEarnings = List.filled(weekStarts.length, 0.0);
          int monthTotalRequests = 0;
          double monthTotalEarnings = 0.0;

          // Conteos y montos por día dentro de cada semana del mes.
          final List<List<int>> weekDayCounts = List.generate(
            weekStarts.length,
            (_) => List.filled(7, 0),
          );
          final List<List<double>> weekDaySegments = List.generate(
            weekStarts.length,
            (_) => List.filled(7, 0.0),
          );
          // Por hora para el día seleccionado.
          final List<double> hourlyEarnings = List.filled(24, 0.0);

          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final ts =
                  (data['completedAt'] ?? data['fecha de terminacion'])
                      as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate().toLocal();
              final valor = _valorDe(data);

              if (dt.month == selectedMonth && dt.year == year) {
                monthTotalRequests += 1;
                monthTotalEarnings += valor;
                for (var i = 0; i < weekStarts.length; i++) {
                  final ws = weekStarts[i];
                  final we = ws.add(const Duration(days: 6));
                  if (!dt.isBefore(ws) && !dt.isAfter(we)) {
                    weekCounts[i] += 1;
                    weekEarnings[i] += valor;
                    final dayIndex = dt.difference(ws).inDays.clamp(0, 6);
                    weekDayCounts[i][dayIndex] += 1;
                    weekDaySegments[i][dayIndex] += valor;
                    break;
                  }
                }
              }

              if (dt.year == selectedDate.year &&
                  dt.month == selectedDate.month &&
                  dt.day == selectedDate.day) {
                hourlyEarnings[dt.hour] += valor;
              }
            } catch (_) {}
          }

          final String formattedMonthEarnings = (monthTotalEarnings % 1 == 0)
              ? integerFmt.format(monthTotalEarnings.toInt())
              : twoDecFmt.format(monthTotalEarnings);

          List<double> selectedWeekDayEarnings = List.filled(7, 0.0);
          List<int> selectedWeekDayCounts = List.filled(7, 0);
          if (weekStarts.isNotEmpty &&
              selectedWeekIndex >= 0 &&
              selectedWeekIndex < weekStarts.length) {
            selectedWeekDayEarnings = List.from(
              weekDaySegments[selectedWeekIndex],
            );
            selectedWeekDayCounts = List.from(weekDayCounts[selectedWeekIndex]);
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                          final int todayWeekIndex = weekStarts.indexWhere((
                            ws,
                          ) {
                            final we = ws.add(const Duration(days: 6));
                            return !now.isBefore(ws) && !now.isAfter(we);
                          });
                          setState(() {
                            viewMode = v;
                            if (todayWeekIndex != -1) {
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
                        titulo: 'Ganancias por hora',
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
                          icon: const Icon(Icons.calendar_today_rounded, size: 16),
                          label: Text(
                            DateFormat('d/MM/yyyy').format(selectedDate),
                          ),
                        ),
                        child: _GraficoDia(hourlyEarnings: hourlyEarnings),
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
                            label: 'Solicitudes mes',
                            value: monthTotalRequests.toString(),
                            color: _amberDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.payments_rounded,
                            label: 'Ganado mes',
                            value: '\$$formattedMonthEarnings',
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
                    color: sel ? AppColores.textPrimary : AppColores.textSecondary,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColores.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) Flexible(child: trailing!),
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
        style: const TextStyle(fontSize: 12.5, color: AppColores.textPrimary),
        items: List.generate(weekStarts.length, (i) {
          final ws = weekStarts[i];
          final we = ws.add(const Duration(days: 6));
          return DropdownMenuItem(
            value: i,
            child: Text(
              '${DateFormat('d/MM').format(ws)} - ${DateFormat('d/MM').format(we)}',
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
  const _GraficoDia({required this.hourlyEarnings});
  final List<double> hourlyEarnings;

  @override
  Widget build(BuildContext context) {
    final max = hourlyEarnings.fold<double>(0, (p, e) => e > p ? e : p);
    final total = hourlyEarnings.fold<double>(0, (p, e) => p + e);

    if (total == 0) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Sin ganancias este día',
            style: TextStyle(color: AppColores.textSecondary),
          ),
        ),
      );
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(24, (h) {
          final val = hourlyEarnings[h];
          final barHeight = max == 0 ? 0.0 : (val / max) * 100.0;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 6,
                  height: val > 0 ? (barHeight < 4 ? 4 : barHeight) : 0,
                  decoration: BoxDecoration(
                    color: AppColores.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                if (h % 3 == 0)
                  Text(
                    h.toString(),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColores.textSecondary,
                    ),
                  ),
              ],
            ),
          );
        }),
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
