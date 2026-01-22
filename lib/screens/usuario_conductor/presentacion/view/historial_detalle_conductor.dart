import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class HistorialDetalleConductor extends StatefulWidget {
  final String conductorId;
  const HistorialDetalleConductor({Key? key, required this.conductorId}) : super(key: key);

  @override
  State<HistorialDetalleConductor> createState() => _HistorialDetalleConductorState();
}

class _HistorialDetalleConductorState extends State<HistorialDetalleConductor> {
  int selectedMonth = DateTime.now().month;
  String viewMode = 'semana'; // 'mes' | 'semana' | 'dia'
  int selectedWeekIndex = 0;
  DateTime selectedDate = DateTime.now();
  final List<String> monthNames = const ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];

  @override
  void initState() {
    super.initState();
    // Initialize locale data for date formatting to avoid LocaleDataException
    initializeDateFormatting('es').then((_) {
      if (mounted) setState(() {});
    });
    // Compute weekStarts for the current selectedMonth/year and set selectedWeekIndex
    final DateTime now = DateTime.now();
    final int year = now.year;
    final DateTime firstDayOfMonth = DateTime(year, selectedMonth, 1);
    final DateTime lastDayOfMonth = (selectedMonth == 12)
        ? DateTime(year + 1, 1, 1).subtract(const Duration(days: 1))
        : DateTime(year, selectedMonth + 1, 1).subtract(const Duration(days: 1));
    DateTime weekStart = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
    final List<DateTime> weekStarts = [];
    while (weekStart.isBefore(lastDayOfMonth) || weekStart.isAtSameMomentAs(lastDayOfMonth)) {
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

  void _showDayDetail(BuildContext context, DateTime date, double earnings, int count, NumberFormat integerFmt, NumberFormat twoDecFmt) {
    final String formatted = (earnings % 1 == 0) ? integerFmt.format(earnings.toInt()) : twoDecFmt.format(earnings);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${DateFormat('EEEE, d/MM/yyyy', 'es').format(date)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solicitudes: $count'),
            const SizedBox(height: 8),
            Text('Ganado: \$$formatted'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Ganancias'),
        backgroundColor: AppColores.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes')
            .where('conductor.id', isEqualTo: widget.conductorId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          // Aggregate per day
          final Map<String, double> earningsByDay = {};
          final Map<String, int> countByDay = {};
          double total = 0.0;

          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              double valor = 0.0;
              final tarifa = data['tarifa'];
              if (tarifa is Map && tarifa['total'] != null) {
                final t = tarifa['total'];
                if (t is num) valor = t.toDouble();
                else valor = double.tryParse(t.toString()) ?? 0.0;
              } else if (data['valor'] != null) {
                final v = data['valor'];
                if (v is num) valor = v.toDouble();
                else valor = double.tryParse(v.toString()) ?? 0.0;
              }

              total += valor;

              final ts = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
              final key = ts != null ? ts.toDate().toLocal().toIso8601String().split('T').first : 'Sin fecha';

              earningsByDay[key] = (earningsByDay[key] ?? 0.0) + valor;
              countByDay[key] = (countByDay[key] ?? 0) + 1;
            } catch (_) {}
          }

          // Sort keys
          final keys = earningsByDay.keys.toList()..sort((a, b) => b.compareTo(a));

          // Formatters
          final NumberFormat integerFmt = NumberFormat.decimalPattern('es');
          final NumberFormat twoDecFmt = NumberFormat('#,##0.00', 'es');

          final now = DateTime.now();
            // Short weekday header like 'Lun' (capitalized) for the title
            final String weekdayAbbrevRaw = DateFormat('E', 'es').format(now);
            final String weekdayAbbrev = weekdayAbbrevRaw.replaceAll('.', '');
            final String weekdayCapital = weekdayAbbrev.isNotEmpty
              ? weekdayAbbrev[0].toUpperCase() + weekdayAbbrev.substring(1)
              : weekdayAbbrev;
            final String headerDate = 'Detalle del día • $weekdayCapital ${now.day}';
          final todayKey = now.toLocal().toIso8601String().split('T').first;
          final int todaysRequests = countByDay[todayKey] ?? 0;
          final double todaysEarnings = earningsByDay[todayKey] ?? 0.0;
          final String formattedTodaysEarnings = (todaysEarnings % 1 == 0)
              ? integerFmt.format(todaysEarnings.toInt())
              : twoDecFmt.format(todaysEarnings);

          // Weeks of selected month: build week ranges (Mon-Sun) that intersect the month
          // weekStarts already computed below; we'll render bars per week

          final int year = now.year;
          final DateTime firstDayOfMonth = DateTime(year, selectedMonth, 1);
          final DateTime lastDayOfMonth = (selectedMonth == 12)
              ? DateTime(year + 1, 1, 1).subtract(const Duration(days: 1))
              : DateTime(year, selectedMonth + 1, 1).subtract(const Duration(days: 1));

          // weekStarts: the Monday of the first week that includes firstDayOfMonth
          DateTime weekStart = firstDayOfMonth.subtract(Duration(days: firstDayOfMonth.weekday - 1));
          final List<DateTime> weekStarts = [];
          while (weekStart.isBefore(lastDayOfMonth) || weekStart.isAtSameMomentAs(lastDayOfMonth)) {
            weekStarts.add(weekStart);
            weekStart = weekStart.add(const Duration(days: 7));
          }

          // Prepare per-week accumulators
          final List<int> weekCounts = List.filled(weekStarts.length, 0);
          final List<double> weekEarnings = List.filled(weekStarts.length, 0.0);
          int monthTotalRequests = 0;
          double monthTotalEarnings = 0.0;

          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final ts = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate().toLocal();
              double valor = 0.0;
              final tarifa = data['tarifa'];
              if (tarifa is Map && tarifa['total'] != null) {
                final t = tarifa['total'];
                if (t is num) valor = t.toDouble();
                else valor = double.tryParse(t.toString()) ?? 0.0;
              } else if (data['valor'] != null) {
                final v = data['valor'];
                if (v is num) valor = v.toDouble();
                else valor = double.tryParse(v.toString()) ?? 0.0;
              }

              // If entry belongs to selected month/year, include in month totals
              if (dt.month == selectedMonth && dt.year == year) {
                monthTotalRequests += 1;
                monthTotalEarnings += valor;

                // find week index
                for (var i = 0; i < weekStarts.length; i++) {
                  final ws = weekStarts[i];
                  final we = ws.add(const Duration(days: 6));
                  if (!dt.isBefore(ws) && !dt.isAfter(we)) {
                    weekCounts[i] += 1;
                    weekEarnings[i] += valor;
                    break;
                  }
                }
              }
            } catch (_) {}
          }

          final int weekTotalRequests = weekCounts.fold<int>(0, (p, e) => p + e);
          final double weekTotalEarnings = weekEarnings.fold<double>(0.0, (p, e) => p + e);

            final String formattedWeekEarnings = (weekTotalEarnings % 1 == 0)
              ? integerFmt.format(weekTotalEarnings.toInt())
              : twoDecFmt.format(weekTotalEarnings);
            final String formattedMonthEarnings = (monthTotalEarnings % 1 == 0)
              ? integerFmt.format(monthTotalEarnings.toInt())
              : twoDecFmt.format(monthTotalEarnings);

          // Build stacked segments per week (for month view): each week contains up to 7 day-values
          List<List<double>> weekDaySegments = List.generate(weekStarts.length, (_) => List.filled(7, 0.0));
          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final ts = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate().toLocal();
              double valor = 0.0;
              final tarifa = data['tarifa'];
              if (tarifa is Map && tarifa['total'] != null) {
                final t = tarifa['total'];
                if (t is num) valor = t.toDouble();
                else valor = double.tryParse(t.toString()) ?? 0.0;
              } else if (data['valor'] != null) {
                final v = data['valor'];
                if (v is num) valor = v.toDouble();
                else valor = double.tryParse(v.toString()) ?? 0.0;
              }

              // assign to week/day segment if within selected month/year
              if (dt.month == selectedMonth && dt.year == year) {
                for (var i = 0; i < weekStarts.length; i++) {
                  final ws = weekStarts[i];
                  final we = ws.add(const Duration(days: 6));
                  if (!dt.isBefore(ws) && !dt.isAfter(we)) {
                    final dayIndex = dt.difference(ws).inDays.clamp(0, 6);
                    weekDaySegments[i][dayIndex] += valor;
                    break;
                  }
                }
              }
            } catch (_) {}
          }

          // Build per-week day counts (Lun-Dom) based on number of solicitudes
          List<List<int>> weekDayCounts = List.generate(weekStarts.length, (_) => List.filled(7, 0));
          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final ts = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate().toLocal();

              for (var i = 0; i < weekStarts.length; i++) {
                final ws = weekStarts[i];
                final we = ws.add(const Duration(days: 6));
                if (!dt.isBefore(ws) && !dt.isAfter(we)) {
                  final dayIndex = dt.difference(ws).inDays.clamp(0, 6);
                  weekDayCounts[i][dayIndex] += 1;
                  break;
                }
              }
            } catch (_) {}
          }

          // For week view: prepare day-by-day earnings for selected week
          List<double> selectedWeekDayEarnings = List.filled(7, 0.0);
          if (weekStarts.isNotEmpty && selectedWeekIndex >= 0 && selectedWeekIndex < weekStarts.length) {
            selectedWeekDayEarnings = List.from(weekDaySegments[selectedWeekIndex]);
          }

          // For week view: prepare day-by-day counts for selected week (Mon-Sun)
          List<int> selectedWeekDayCounts = List.filled(7, 0);
          if (weekStarts.isNotEmpty && selectedWeekIndex >= 0 && selectedWeekIndex < weekStarts.length) {
            selectedWeekDayCounts = List.from(weekDayCounts[selectedWeekIndex]);
          }

          // For day view: prepare hourly earnings for selectedDate
          List<double> hourlyEarnings = List.filled(24, 0.0);
          for (var d in docs) {
            try {
              final data = d.data() as Map<String, dynamic>;
              final ts = (data['completedAt'] ?? data['fecha de terminacion']) as Timestamp?;
              if (ts == null) continue;
              final dt = ts.toDate().toLocal();
              if (dt.year == selectedDate.year && dt.month == selectedDate.month && dt.day == selectedDate.day) {
                double valor = 0.0;
                final tarifa = data['tarifa'];
                if (tarifa is Map && tarifa['total'] != null) {
                  final t = tarifa['total'];
                  if (t is num) valor = t.toDouble();
                  else valor = double.tryParse(t.toString()) ?? 0.0;
                } else if (data['valor'] != null) {
                  final v = data['valor'];
                  if (v is num) valor = v.toDouble();
                  else valor = double.tryParse(v.toString()) ?? 0.0;
                }
                hourlyEarnings[dt.hour] += valor;
              }
            } catch (_) {}
          }


          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30), // espacio entre AppBar y detalle del día
                  // Encabezado centrado sin contenedor gris
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(headerDate, style: TextStyle(fontSize: 14, color: AppColores.textSecondary, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text('\$$formattedTodaysEarnings', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColores.textPrimary)),
                        const SizedBox(height: 8),
                        Text('${todaysRequests.toString()} solicitudes', style: const TextStyle(fontSize: 14, color: AppColores.textSecondary)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30), // espacio entre detalle y el cuadro siguiente

                  // Chart area: show month/week/day depending on viewMode
                  if (viewMode == 'mes')
                    Card(
                      color: AppColores.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ganado por semanas (Mes)', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 140,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(weekStarts.length, (i) {
                                  // Usar conteos por día (weekDayCounts) en lugar de montos
                                  final segments = weekDayCounts[i];
                                  final weekTotal = segments.fold<int>(0, (p, e) => p + e);
                                  final maxWeekly = weekCounts.fold<int>(0, (p, e) => e > p ? e : p);
                                  final barMax = maxWeekly == 0 ? 1 : maxWeekly;
                                  final weekLabel = DateFormat('d/MM').format(weekStarts[i]);
                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            // switch to week view for this week
                                            setState(() {
                                              viewMode = 'semana';
                                              selectedWeekIndex = i;
                                            });
                                          },
                                          child: Column(
                                            children: [
                                              Text(weekTotal.toString(), style: const TextStyle(fontSize: 12, color: AppColores.textSecondary)),
                                              const SizedBox(height: 6),
                                              Container(
                                                height: 90,
                                                alignment: Alignment.bottomCenter,
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  children: segments.map((seg) {
                                                    double segHeight = (seg / barMax) * 90.0;
                                                    if (seg > 0 && segHeight < 6.0) segHeight = 6.0;
                                                    return Container(
                                                      width: 18,
                                                      height: segHeight,
                                                      decoration: BoxDecoration(color: AppColores.primary.withOpacity(0.6), borderRadius: BorderRadius.circular(0)),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(weekLabel, style: const TextStyle(fontSize: 12, color: AppColores.textSecondary)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total mes: $monthTotalRequests solicitudes', style: const TextStyle(color: AppColores.textSecondary)),
                                Text('Ganado mes: \$$formattedMonthEarnings', style: const TextStyle(color: AppColores.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (viewMode == 'semana' && weekStarts.isNotEmpty)
                    Card(
                      color: AppColores.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Semana: ', style: TextStyle(color: AppColores.textSecondary)),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: selectedWeekIndex,
                                  items: List.generate(weekStarts.length, (i) {
                                    final ws = weekStarts[i];
                                    final we = ws.add(const Duration(days: 6));
                                    return DropdownMenuItem(value: i, child: Text('${DateFormat('d/MM').format(ws)} - ${DateFormat('d/MM').format(we)}'));
                                  }),
                                  onChanged: (v) { if (v == null) return; setState(() { selectedWeekIndex = v; }); },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 100,
                              child: Column(
                                children: [
                                  // Baseline with small rounded pills above it (like the photo)
                                  SizedBox(
                                    height: 44,
                                    child: Stack(
                                      children: [
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            height: 6,
                                            margin: const EdgeInsets.symmetric(horizontal: 16),
                                            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(6)),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Builder(builder: (context) {
                                            final int maxCountInSelectedWeek = selectedWeekDayCounts.fold<int>(0, (p, e) => e > p ? e : p);
                                            final double maxForDiv = maxCountInSelectedWeek == 0 ? 1.0 : maxCountInSelectedWeek.toDouble();
                                            return Row(
                                              children: List.generate(7, (i) {
                                                final count = selectedWeekDayCounts[i];
                                                final bool hasData = count > 0;
                                                final pillColor = hasData ? AppColores.primary : Colors.grey.shade200;
                                                final DateTime dayDate = weekStarts[selectedWeekIndex].add(Duration(days: i));
                                                final double dayEarnings = selectedWeekDayEarnings.length > i ? selectedWeekDayEarnings[i] : 0.0;
                                                final double pillHeight = hasData ? (8.0 + (count.toDouble() / maxForDiv) * 36.0) : 8.0;
                                                return Expanded(
                                                  child: Align(
                                                    alignment: Alignment.bottomCenter,
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(6),
                                                      onTap: () => _showDayDetail(context, dayDate, dayEarnings, count, integerFmt, twoDecFmt),
                                                      child: Container(
                                                        width: 36,
                                                        height: pillHeight,
                                                        margin: const EdgeInsets.symmetric(horizontal: 6),
                                                        decoration: BoxDecoration(
                                                          color: pillColor,
                                                          borderRadius: BorderRadius.circular(6),
                                                          boxShadow: [BoxShadow(color: Colors.black12, offset: Offset(0, 1), blurRadius: 1)],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            );
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Day names (Lun, Mar, ...)
                                  Row(
                                    children: List.generate(7, (i) {
                                      String dayLabel = DateFormat('E', 'es').format(weekStarts[selectedWeekIndex].add(Duration(days: i))).replaceAll('.', '');
                                      if (dayLabel.length > 3) dayLabel = dayLabel.substring(0, 3);
                                      dayLabel = dayLabel[0].toUpperCase() + dayLabel.substring(1);
                                      return Expanded(
                                        child: Center(child: Text(dayLabel, style: const TextStyle(fontSize: 12, color: AppColores.textSecondary))),
                                      );
                                    }),
                                  ),

                                  const SizedBox(height: 4),

                                  // Dates (numbers)
                                  Row(
                                    children: List.generate(7, (i) {
                                      final dayNum = weekStarts[selectedWeekIndex].add(Duration(days: i)).day;
                                      return Expanded(
                                        child: Center(child: Text(dayNum.toString(), style: const TextStyle(fontSize: 12, color: AppColores.textSecondary))),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (viewMode == 'dia')
                    Card(
                      color: AppColores.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('Día: ', style: TextStyle(color: AppColores.textSecondary)),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                                  if (picked != null) setState(() { selectedDate = picked; });
                                },
                                child: Text('${DateFormat('d/MM/yyyy').format(selectedDate)}'),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 140,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(24, (h) {
                                  final val = hourlyEarnings[h];
                                  final max = hourlyEarnings.reduce((a, b) => a > b ? a : b);
                                  final barHeight = max == 0 ? 0.0 : (val / max) * 90.0;
                                  return Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(val.toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: AppColores.textSecondary)),
                                        const SizedBox(height: 4),
                                        Container(height: 90, alignment: Alignment.bottomCenter, child: Container(width: 8, height: barHeight, decoration: BoxDecoration(color: AppColores.primary, borderRadius: BorderRadius.circular(4)))),
                                        const SizedBox(height: 4),
                                        Text(h.toString(), style: const TextStyle(fontSize: 10, color: AppColores.textSecondary)),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Button-style selectors below the chart
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Wrap(
                          spacing: 8,
                          children: ['semana', 'mes'].map((v) {
                            return ChoiceChip(
                              label: Text(v.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              selected: viewMode == v,
                              onSelected: (s) {
                                if (!s) return;
                                if (v == 'semana' && weekStarts.isNotEmpty) {
                                  final int todayWeekIndex = weekStarts.indexWhere((ws) {
                                    final we = ws.add(const Duration(days: 6));
                                    return !now.isBefore(ws) && !now.isAfter(we);
                                  });
                                  setState(() {
                                    viewMode = v;
                                    if (todayWeekIndex != -1) selectedWeekIndex = todayWeekIndex;
                                  });
                                } else {
                                  setState(() { viewMode = v; });
                                }
                              },
                              selectedColor: AppColores.primary,
                              backgroundColor: AppColores.surface,
                              labelStyle: TextStyle(color: viewMode == v ? Colors.white : AppColores.textPrimary),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (viewMode == 'mes')
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(12, (i) {
                              final m = i + 1;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                        child: ChoiceChip(
                                          label: Text(monthNames[i], style: const TextStyle(fontSize: 12)),
                                          selected: selectedMonth == m,
                                          onSelected: (s) { if (s) setState(() { selectedMonth = m; selectedWeekIndex = 0; }); },
                                          selectedColor: AppColores.primary,
                                          backgroundColor: AppColores.surface,
                                          labelStyle: TextStyle(color: selectedMonth == m ? Colors.white : AppColores.textPrimary),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      );
                            }),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Card(
                    color: AppColores.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Solicitudes mes', style: TextStyle(fontSize: 12, color: AppColores.textSecondary)),
                              const SizedBox(height: 6),
                              Text(monthTotalRequests.toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColores.textPrimary)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Ganado mes', style: TextStyle(fontSize: 12, color: AppColores.textSecondary)),
                              const SizedBox(height: 6),
                              Text('\$$formattedMonthEarnings', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColores.textPrimary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
