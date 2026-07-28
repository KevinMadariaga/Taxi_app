import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

/// Resultado de [HistorialDetalleConductorViewModel.computeAggregation]:
/// todos los números/strings ya calculados que `HistorialDetalleConductor`
/// necesita para pintar hero, gráficos y stat cards — el `build()` solo lee
/// estos campos, no agrega ni formatea nada por su cuenta.
class HistorialDetalleAggregation {
  const HistorialDetalleAggregation({
    required this.headerDate,
    required this.todaysRequests,
    required this.formattedTodaysEarnings,
    required this.weekStarts,
    required this.weekCounts,
    required this.monthTotalRequests,
    required this.formattedMonthEarnings,
    required this.selectedWeekDayEarnings,
    required this.selectedWeekDayCounts,
    required this.weekTotalRequests,
    required this.formattedWeekEarnings,
    required this.selectedDateRequests,
    required this.formattedSelectedDateEarnings,
    required this.hourlyEarnings,
    required this.hourlyRequests,
    required this.statLabel1,
    required this.statCount1,
    required this.statLabel2,
    required this.statEarnings,
    required this.integerFmt,
    required this.twoDecFmt,
  });

  final String headerDate;
  final int todaysRequests;
  final String formattedTodaysEarnings;

  final List<DateTime> weekStarts;
  final List<int> weekCounts;

  final int monthTotalRequests;
  final String formattedMonthEarnings;

  final List<double> selectedWeekDayEarnings;
  final List<int> selectedWeekDayCounts;
  final int weekTotalRequests;
  final String formattedWeekEarnings;

  final int selectedDateRequests;
  final String formattedSelectedDateEarnings;

  final List<double> hourlyEarnings;
  final List<int> hourlyRequests;

  final String statLabel1;
  final int statCount1;
  final String statLabel2;
  final String statEarnings;

  /// Formatters reutilizados por la View para formatear montos puntuales
  /// (ej. el detalle de un día tocado en el gráfico semanal).
  final NumberFormat integerFmt;
  final NumberFormat twoDecFmt;
}

/// Lógica de cálculo pura para `HistorialDetalleConductor`.
///
/// Clase Dart plana (sin `ChangeNotifier`): la vista la instancia como
/// campo y llama sus métodos directamente, conservando `setState` en la
/// vista. No depende de `BuildContext` ni construye widgets.
class HistorialDetalleConductorViewModel {
  /// Extrae el valor monetario de una solicitud (tarifa.total o valor).
  double valorDe(Map<String, dynamic> data) {
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

  /// Calcula el inicio (lunes) de cada semana que interseca el mes [month]
  /// del año [year].
  List<DateTime> computeWeekStarts(int month, int year) {
    final DateTime firstDayOfMonth = DateTime(year, month, 1);
    final DateTime lastDayOfMonth = (month == 12)
        ? DateTime(year + 1, 1, 1).subtract(const Duration(days: 1))
        : DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
    DateTime weekStart = firstDayOfMonth.subtract(
      Duration(days: firstDayOfMonth.weekday - 1),
    );
    final List<DateTime> weekStarts = [];
    while (weekStart.isBefore(lastDayOfMonth) ||
        weekStart.isAtSameMomentAs(lastDayOfMonth)) {
      weekStarts.add(weekStart);
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return weekStarts;
  }

  /// Índice dentro de [weekStarts] cuya semana (7 días desde el inicio)
  /// contiene [date]. `null` si ninguna coincide.
  int? findWeekIndexForDate(List<DateTime> weekStarts, DateTime date) {
    for (var i = 0; i < weekStarts.length; i++) {
      final ws = weekStarts[i];
      if (!date.isBefore(ws) &&
          date.isBefore(ws.add(const Duration(days: 7)))) {
        return i;
      }
    }
    return null;
  }

  /// Formatea un monto: sin decimales si es entero, con 2 decimales si no.
  String formatEarnings(
    double value,
    NumberFormat integerFmt,
    NumberFormat twoDecFmt,
  ) {
    return value % 1 == 0
        ? integerFmt.format(value.toInt())
        : twoDecFmt.format(value);
  }

  /// Agrega [docs] (solicitudes completadas del conductor) por día, semana
  /// del mes seleccionado y hora del día seleccionado, y arma los valores ya
  /// formateados que la View necesita para el modo actual (`viewMode`).
  ///
  /// Antes esta agregación completa (dos loops sobre `docs`, cálculo de
  /// semanas/horas/totales, y formateo) vivía dentro de `build()`.
  HistorialDetalleAggregation computeAggregation({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required int selectedMonth,
    required int selectedWeekIndex,
    required DateTime selectedDate,
    required String viewMode,
    required DateTime now,
  }) {
    final NumberFormat integerFmt = NumberFormat.decimalPattern('es');
    final NumberFormat twoDecFmt = NumberFormat('#,##0.00', 'es');

    // ── Agregación por día (para "hoy") ──────────────────────────────
    final Map<String, double> earningsByDay = {};
    final Map<String, int> countByDay = {};
    for (final d in docs) {
      try {
        final data = d.data();
        final valor = valorDe(data);
        final ts =
            (data['completedAt'] ?? data['fecha de terminacion'])
                as Timestamp?;
        final key = ts != null
            ? ts.toDate().toLocal().toIso8601String().split('T').first
            : 'Sin fecha';
        earningsByDay[key] = (earningsByDay[key] ?? 0.0) + valor;
        countByDay[key] = (countByDay[key] ?? 0) + 1;
      } catch (e, st) {
        ErrorReporter.report(
          e,
          st,
          reason: 'historial_detalle_conductor_viewmodel',
        );
      }
    }

    final String weekdayAbbrevRaw = DateFormat('E', 'es').format(now);
    final String weekdayAbbrev = weekdayAbbrevRaw.replaceAll('.', '');
    final String weekdayCapital = weekdayAbbrev.isNotEmpty
        ? weekdayAbbrev[0].toUpperCase() + weekdayAbbrev.substring(1)
        : weekdayAbbrev;
    final String headerDate = '$weekdayCapital ${now.day} de hoy';
    final todayKey = now.toLocal().toIso8601String().split('T').first;
    final int todaysRequests = countByDay[todayKey] ?? 0;
    final double todaysEarnings = earningsByDay[todayKey] ?? 0.0;
    final String formattedTodaysEarnings = formatEarnings(
      todaysEarnings,
      integerFmt,
      twoDecFmt,
    );

    final int year = now.year;
    final List<DateTime> weekStarts = computeWeekStarts(selectedMonth, year);

    final List<int> weekCounts = List.filled(weekStarts.length, 0);
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
    final List<int> hourlyRequests = List.filled(24, 0);

    for (final d in docs) {
      try {
        final data = d.data();
        final ts =
            (data['completedAt'] ?? data['fecha de terminacion'])
                as Timestamp?;
        if (ts == null) continue;
        final dt = ts.toDate().toLocal();
        final valor = valorDe(data);

        if (dt.month == selectedMonth && dt.year == year) {
          monthTotalRequests += 1;
          monthTotalEarnings += valor;
          for (var i = 0; i < weekStarts.length; i++) {
            final ws = weekStarts[i];
            if (!dt.isBefore(ws) &&
                dt.isBefore(ws.add(const Duration(days: 7)))) {
              weekCounts[i] += 1;
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
          hourlyRequests[dt.hour] += 1;
        }
      } catch (e, st) {
        ErrorReporter.report(
          e,
          st,
          reason: 'historial_detalle_conductor_viewmodel',
        );
      }
    }

    final String formattedMonthEarnings = formatEarnings(
      monthTotalEarnings,
      integerFmt,
      twoDecFmt,
    );

    List<double> selectedWeekDayEarnings = List.filled(7, 0.0);
    List<int> selectedWeekDayCounts = List.filled(7, 0);
    if (weekStarts.isNotEmpty &&
        selectedWeekIndex >= 0 &&
        selectedWeekIndex < weekStarts.length) {
      selectedWeekDayEarnings = List.from(weekDaySegments[selectedWeekIndex]);
      selectedWeekDayCounts = List.from(weekDayCounts[selectedWeekIndex]);
    }

    final int weekTotalRequests = selectedWeekDayCounts.fold(
      0,
      (p, e) => p + e,
    );
    final double weekTotalEarnings = selectedWeekDayEarnings.fold(
      0.0,
      (p, e) => p + e,
    );
    final String formattedWeekEarnings = formatEarnings(
      weekTotalEarnings,
      integerFmt,
      twoDecFmt,
    );

    final String selectedDateKey = selectedDate
        .toLocal()
        .toIso8601String()
        .split('T')
        .first;
    final int selectedDateRequests = countByDay[selectedDateKey] ?? 0;
    final double selectedDateEarnings = earningsByDay[selectedDateKey] ?? 0.0;
    final String formattedSelectedDateEarnings = formatEarnings(
      selectedDateEarnings,
      integerFmt,
      twoDecFmt,
    );

    final String statLabel1 = viewMode == 'dia'
        ? 'Solicitudes día'
        : viewMode == 'semana'
        ? 'Solicitudes semana'
        : 'Solicitudes mes';
    final int statCount1 = viewMode == 'dia'
        ? selectedDateRequests
        : viewMode == 'semana'
        ? weekTotalRequests
        : monthTotalRequests;
    final String statLabel2 = viewMode == 'dia'
        ? 'Ganado día'
        : viewMode == 'semana'
        ? 'Ganado semana'
        : 'Ganado mes';
    final String statEarnings = viewMode == 'dia'
        ? formattedSelectedDateEarnings
        : viewMode == 'semana'
        ? formattedWeekEarnings
        : formattedMonthEarnings;

    return HistorialDetalleAggregation(
      headerDate: headerDate,
      todaysRequests: todaysRequests,
      formattedTodaysEarnings: formattedTodaysEarnings,
      weekStarts: weekStarts,
      weekCounts: weekCounts,
      monthTotalRequests: monthTotalRequests,
      formattedMonthEarnings: formattedMonthEarnings,
      selectedWeekDayEarnings: selectedWeekDayEarnings,
      selectedWeekDayCounts: selectedWeekDayCounts,
      weekTotalRequests: weekTotalRequests,
      formattedWeekEarnings: formattedWeekEarnings,
      selectedDateRequests: selectedDateRequests,
      formattedSelectedDateEarnings: formattedSelectedDateEarnings,
      hourlyEarnings: hourlyEarnings,
      hourlyRequests: hourlyRequests,
      statLabel1: statLabel1,
      statCount1: statCount1,
      statLabel2: statLabel2,
      statEarnings: statEarnings,
      integerFmt: integerFmt,
      twoDecFmt: twoDecFmt,
    );
  }
}
