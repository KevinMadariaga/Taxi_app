import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taxi_app/core/app_colores.dart';

/// Hoja de detalles del viaje (lado cliente y conductor).
/// Muestra a la contraparte (nombre + calificación), vehículo, direcciones,
/// valor y método de pago con icono. Diseño moderno y responsivo.
class TripDetailsSheet extends StatelessWidget {
  const TripDetailsSheet({
    super.key,
    required this.tituloPersona,
    required this.nombrePersona,
    required this.fotoPersona,
    required this.calificacion,
    required this.totalCalificaciones,
    required this.fotoVehiculo,
    required this.placa,
    required this.direccionRecoger,
    required this.direccionDestino,
    required this.valorServicio,
    required this.metodoPago,
    this.labelRecoger = 'Recoger en',
    this.mostrarVehiculo = true,
    this.mostrarCalificacion = true,
  });

  final String tituloPersona; // 'Conductor' o 'Cliente'
  final String nombrePersona;
  final String fotoPersona;
  final double calificacion;
  final int totalCalificaciones;
  final String fotoVehiculo;
  final String placa;
  final String direccionRecoger;
  final String direccionDestino;
  final double valorServicio;
  final String metodoPago;
  final String labelRecoger;
  final bool mostrarVehiculo;
  final bool mostrarCalificacion;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColores.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Detalles del viaje',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColores.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              // Persona (contraparte) + vehículo.
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColores.primary,
                    backgroundImage:
                        fotoPersona.isNotEmpty ? NetworkImage(fotoPersona) : null,
                    child: fotoPersona.isEmpty
                        ? const Icon(Icons.person,
                            size: 32, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tituloPersona,
                          style: const TextStyle(
                            color: AppColores.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nombrePersona.isEmpty ? '—' : nombrePersona,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: AppColores.textPrimary,
                          ),
                        ),
                        if (mostrarCalificacion) ...[
                          const SizedBox(height: 4),
                          _Estrellas(
                            valor: calificacion,
                            total: totalCalificaciones,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (mostrarVehiculo) ...[
                    const SizedBox(width: 10),
                    _VehiculoChip(foto: fotoVehiculo, placa: placa),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: AppColores.borderSubtle),
              const SizedBox(height: 14),
              _DireccionRow(
                icon: Icons.my_location,
                color: AppColores.success,
                label: labelRecoger,
                value: direccionRecoger.isEmpty ? '—' : direccionRecoger,
              ),
              const SizedBox(height: 12),
              _DireccionRow(
                icon: Icons.location_on,
                color: AppColores.error,
                label: 'Destino',
                value: direccionDestino.isEmpty ? '—' : direccionDestino,
              ),
              const SizedBox(height: 16),
              // Valor + método de pago.
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
                              color: AppColores.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currency(valorServicio),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: AppColores.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MetodoPagoChip(metodo: metodoPago),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _currency(double value) {
    final f = NumberFormat.currency(
      locale: 'es_CO',
      symbol: r'$',
      decimalDigits: 0,
    );
    return f.format(value);
  }
}

class _Estrellas extends StatelessWidget {
  const _Estrellas({required this.valor, required this.total});
  final double valor;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 0 && valor <= 0) {
      return const Text(
        'Conductor nuevo',
        style: TextStyle(fontSize: 12, color: AppColores.textSecondary),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          IconData icon;
          if (valor >= i + 1) {
            icon = Icons.star_rounded;
          } else if (valor >= i + 0.5) {
            icon = Icons.star_half_rounded;
          } else {
            icon = Icons.star_outline_rounded;
          }
          return Icon(icon, size: 16, color: AppColores.warning);
        }),
        const SizedBox(width: 4),
        Text(
          '${valor.toStringAsFixed(1)} ($total)',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColores.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _VehiculoChip extends StatelessWidget {
  const _VehiculoChip({required this.foto, required this.placa});
  final String foto;
  final String placa;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 72,
            height: 54,
            color: AppColores.grey200,
            child: foto.isNotEmpty
                ? Image.network(foto, fit: BoxFit.cover)
                : const Icon(Icons.local_taxi, color: AppColores.grey400),
          ),
        ),
        if (placa.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColores.textPrimary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              placa.toUpperCase(),
              style: const TextStyle(
                color: AppColores.textWhite,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DireccionRow extends StatelessWidget {
  const _DireccionRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColores.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColores.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetodoPagoChip extends StatelessWidget {
  const _MetodoPagoChip({required this.metodo});
  final String metodo;

  @override
  Widget build(BuildContext context) {
    final lower = metodo.toLowerCase();
    Widget icono;
    String label;
    if (lower.contains('efectivo') || lower.contains('cash')) {
      icono = const Icon(Icons.payments_rounded,
          color: AppColores.success, size: 22);
      label = 'Efectivo';
    } else if (lower.contains('nequi')) {
      icono = Image.asset(
        'assets/img/nequi.png',
        width: 24,
        height: 24,
        errorBuilder: (_, _, _) => const Icon(
          Icons.account_balance_wallet,
          color: AppColores.primary,
          size: 22,
        ),
      );
      label = 'Nequi';
    } else if (lower.contains('transfer') || lower.contains('banco')) {
      icono = const Icon(Icons.account_balance,
          color: AppColores.secondary, size: 22);
      label = 'Transferencia';
    } else {
      icono =
          const Icon(Icons.payment, color: AppColores.textSecondary, size: 22);
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
          icono,
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
