/// Reglas de "Pedir para más tarde".
///
/// El servidor sale a buscar conductor 10 min antes de la hora
/// (`ANTICIPACION_PROGRAMADA_MS`), así que el mínimo debe dejar ese margen.
const Duration anticipacionMinimaProgramada = Duration(minutes: 30);
const Duration anticipacionMaximaProgramada = Duration(days: 7);
const int minutosEntreHorarios = 15;

/// Días que se pueden elegir, el de hoy primero. Sale de los horarios reales:
/// a las 11:50 p. m. "hoy" ya no tiene ninguno y no se ofrece.
List<DateTime> diasProgramables(DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  return [
    for (var i = 0; i <= anticipacionMaximaProgramada.inDays; i++)
      DateTime(hoy.year, hoy.month, hoy.day + i),
  ].where((d) => horariosProgramables(d, ahora).isNotEmpty).toList();
}

/// Horarios de [dia] dentro de la ventana permitida, cada
/// [minutosEntreHorarios].
List<DateTime> horariosProgramables(DateTime dia, DateTime ahora) {
  final minimo = ahora.add(anticipacionMinimaProgramada);
  final maximo = ahora.add(anticipacionMaximaProgramada);
  final horarios = <DateTime>[];
  for (var m = 0; m < 24 * 60; m += minutosEntreHorarios) {
    final h = DateTime(dia.year, dia.month, dia.day, 0, m);
    if (!h.isBefore(minimo) && !h.isAfter(maximo)) horarios.add(h);
  }
  return horarios;
}

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
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

/// "Hoy", "Mañana" o "vie 14 nov".
String textoDia(DateTime dia, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final diferencia = DateTime(
    dia.year,
    dia.month,
    dia.day,
  ).difference(hoy).inHours;
  if (diferencia <= 0) return 'Hoy';
  if (diferencia <= 25) return 'Mañana'; // 25: día de 25 h por cambio de hora
  return '${_dias[dia.weekday - 1]} ${dia.day} ${_meses[dia.month - 1]}';
}

/// "3:30 p. m."
String textoHora(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  final m = f.minute.toString().padLeft(2, '0');
  return '$h:$m ${f.hour < 12 ? 'a. m.' : 'p. m.'}';
}

/// "Hoy, 3:30 p. m."
String textoFechaProgramada(DateTime f, DateTime ahora) =>
    '${textoDia(f, ahora)}, ${textoHora(f)}';
