import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';

const Color kHistorialAmberDark = Color(0xFFB38F00);

/// Formatea un número como pesos CO: `$12.000`.
String formatPesos(double value) {
  final intVal = value.round();
  final s = intVal.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${intVal < 0 ? '-' : ''}\$${buf.toString()}';
}

/// Acepta num o string numérico y devuelve pesos formateados.
String pesosFrom(dynamic value) {
  final n = value is num
      ? value.toDouble()
      : double.tryParse(
              value.toString().replaceAll(RegExp(r'[^0-9.\-]'), ''),
            ) ??
            0;
  return formatPesos(n);
}

/// Tarjeta de un viaje en el historial (cliente o conductor).
class HistorialViajeCard extends StatelessWidget {
  const HistorialViajeCard({
    super.key,
    required this.destinoFuture,
    required this.destinoFallback,
    required this.fecha,
    required this.valor,
    required this.calificacion,
    required this.onTap,
    this.isMoto = false,
  });

  final Future<String> destinoFuture;
  final String destinoFallback;
  final String? fecha;
  final String valor;
  final double calificacion;
  final VoidCallback onTap;
  final bool isMoto;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColores.borderSubtle),
      ),
      color: AppColores.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppColores.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMoto ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String>(
                      future: destinoFuture,
                      builder: (context, snap) {
                        final text =
                            snap.connectionState == ConnectionState.waiting
                            ? destinoFallback
                            : (snap.data ?? destinoFallback);
                        return Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColores.textPrimary,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.event_rounded,
                          size: 14,
                          color: AppColores.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            fecha ?? 'Fecha no disponible',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColores.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColores.success,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MiniRating(valor: calificacion),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRating extends StatelessWidget {
  const _MiniRating({required this.valor});
  final double valor;

  @override
  Widget build(BuildContext context) {
    final tiene = valor > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tiene
            ? AppColores.primary.withValues(alpha: 0.15)
            : AppColores.grey200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 14,
            color: tiene ? AppColores.primary : AppColores.grey400,
          ),
          const SizedBox(width: 3),
          Text(
            tiene ? valor.toStringAsFixed(1) : '–',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tiene ? AppColores.textPrimary : AppColores.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío / error con icono y mensaje.
class HistorialEstadoMensaje extends StatelessWidget {
  const HistorialEstadoMensaje({
    super.key,
    required this.icon,
    required this.titulo,
    required this.subtitulo,
  });
  final IconData icon;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColores.grey200,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 42, color: AppColores.grey400),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColores.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de detalle de viaje (cliente o conductor).
class DetalleViajeDialog extends StatelessWidget {
  const DetalleViajeDialog({
    super.key,
    required this.destino,
    required this.persona,
    required this.tituloPersona,
    required this.calificacion,
    required this.valor,
    required this.metodoPago,
  });

  final String destino;
  final String persona;
  final String tituloPersona;
  final double calificacion;
  final String valor;
  final String metodoPago;

  @override
  Widget build(BuildContext context) {
    final esNequi = metodoPago.toLowerCase().contains('nequi');
    final score = calificacion.clamp(0, 5).toDouble();
    final llenas = score.floor();
    final media = (score - llenas) >= 0.5;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                decoration: const BoxDecoration(
                  color: AppColores.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Center(
                      child: Text(
                        'Detalle del viaje',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close,
                              color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppColores.error.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: AppColores.error,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            destino,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColores.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColores.primary.withValues(
                        alpha: 0.18,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: kHistorialAmberDark,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      persona,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColores.textPrimary,
                      ),
                    ),
                    Text(
                      tituloPersona,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final star = i < llenas;
                        final half = i == llenas && media;
                        return Icon(
                          star
                              ? Icons.star_rounded
                              : half
                              ? Icons.star_half_rounded
                              : Icons.star_outline_rounded,
                          size: 30,
                          color: (star || half)
                              ? AppColores.primary
                              : AppColores.grey300,
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      score > 0
                          ? '${score.toStringAsFixed(1)} / 5'
                          : 'Sin calificación',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColores.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColores.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColores.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Valor del servicio',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColores.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  valor,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppColores.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _MetodoPagoChip(metodo: metodoPago, esNequi: esNequi),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetodoPagoChip extends StatelessWidget {
  const _MetodoPagoChip({required this.metodo, required this.esNequi});
  final String metodo;
  final bool esNequi;

  @override
  Widget build(BuildContext context) {
    final m = metodo.toLowerCase();
    IconData icon;
    String label;
    if (m.contains('efectivo') || m.contains('cash')) {
      icon = Icons.payments_rounded;
      label = 'Efectivo';
    } else if (m.contains('nequi')) {
      icon = Icons.account_balance_wallet;
      label = 'Nequi';
    } else if (m.contains('transfer') || m.contains('banco')) {
      icon = Icons.account_balance;
      label = 'Transferencia';
    } else {
      icon = Icons.payment;
      label = metodo.isEmpty ? '—' : metodo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColores.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColores.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          esNequi
              ? Image.asset(
                  'assets/img/nequi.png',
                  width: 24,
                  height: 24,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.account_balance_wallet,
                    color: AppColores.secondary,
                    size: 22,
                  ),
                )
              : Icon(icon, color: AppColores.secondary, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColores.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
