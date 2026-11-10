import 'package:flutter/material.dart';
import 'package:taxi_app/caracteristicas/viaje_pendiente/dominio/programacion_viaje.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Elige día y hora de "Pedir para más tarde". Devuelve la fecha, o `null` si
/// se cierra sin confirmar.
Future<DateTime?> mostrarProgramarViajeSheet(
  BuildContext context, {
  DateTime? ahora,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ProgramarViajeSheet(ahora: ahora ?? DateTime.now()),
  );
}

class _ProgramarViajeSheet extends StatefulWidget {
  const _ProgramarViajeSheet({required this.ahora});

  final DateTime ahora;

  @override
  State<_ProgramarViajeSheet> createState() => _ProgramarViajeSheetState();
}

class _ProgramarViajeSheetState extends State<_ProgramarViajeSheet> {
  late final List<DateTime> _dias = diasProgramables(widget.ahora);
  late DateTime _dia = _dias.first;
  late DateTime _hora = horariosProgramables(_dia, widget.ahora).first;

  void _elegirDia(DateTime dia) {
    final horarios = horariosProgramables(dia, widget.ahora);
    setState(() {
      _dia = dia;
      // Conserva la hora elegida si existe en el día nuevo.
      _hora = horarios.firstWhere(
        (h) => h.hour == _hora.hour && h.minute == _hora.minute,
        orElse: () => horarios.first,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final horarios = horariosProgramables(_dia, widget.ahora);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pedir para más tarde',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Empezamos a buscar tu conductor 10 minutos antes y te avisamos '
              'cuando lo encontremos.',
              style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<DateTime>(
              initialValue: _dia,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Día'),
              items: [
                for (final d in _dias)
                  DropdownMenuItem(
                    value: d,
                    child: Text(textoDia(d, widget.ahora)),
                  ),
              ],
              onChanged: (d) {
                if (d != null) _elegirDia(d);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DateTime>(
              // La key rehace el campo al cambiar de día: su valor inicial
              // solo se lee al crearlo, y las horas del día anterior ya no
              // existen en la lista nueva.
              key: ValueKey(_dia),
              initialValue: _hora,
              isExpanded: true,
              menuMaxHeight: 320,
              decoration: const InputDecoration(labelText: 'Hora'),
              items: [
                for (final h in horarios)
                  DropdownMenuItem(value: h, child: Text(textoHora(h))),
              ],
              onChanged: (h) {
                if (h != null) setState(() => _hora = h);
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColores.primary,
                  foregroundColor: AppColores.ink900,
                ),
                onPressed: () => Navigator.of(context).pop(_hora),
                icon: const Icon(Icons.event_available_rounded),
                label: Text(
                  'Programar: ${textoFechaProgramada(_hora, widget.ahora)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
