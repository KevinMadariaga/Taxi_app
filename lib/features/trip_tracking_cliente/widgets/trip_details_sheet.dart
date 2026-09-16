import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

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
                    color: context.palette.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Detalles del viaje',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              // Persona (contraparte) + vehículo.
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColores.primary,
                    backgroundImage: fotoPersona.isNotEmpty
                        ? NetworkImage(fotoPersona)
                        : null,
                    child: fotoPersona.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 32,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tituloPersona,
                          style: TextStyle(
                            color: context.palette.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nombrePersona.isEmpty ? '—' : nombrePersona,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: context.palette.textPrimary,
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
              Divider(height: 1, color: context.palette.borderSubtle),
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
                  color: context.palette.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Valor del servicio',
                            style: TextStyle(
                              color: context.palette.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currency(valorServicio),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: context.palette.textPrimary,
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
    // Formatea el número y antepone el signo peso a mano: dejarle la
    // posición del símbolo al patrón de `es_CO` de NumberFormat.currency
    // podía terminar mostrándolo después del valor.
    final f = NumberFormat.decimalPattern('es_CO');
    return '\$${f.format(value)}';
  }
}

class _Estrellas extends StatelessWidget {
  const _Estrellas({required this.valor, required this.total});
  final double valor;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 0 && valor <= 0) {
      return Text(
        'Conductor nuevo',
        style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
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
          valor.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.palette.textSecondary,
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
            color: context.palette.grey200,
            child: foto.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: foto,
                    fit: BoxFit.cover,
                    memCacheWidth: 144,
                    memCacheHeight: 108,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) =>
                        Icon(Icons.local_taxi, color: context.palette.grey400),
                  )
                : Icon(Icons.local_taxi, color: context.palette.grey400),
          ),
        ),
        if (placa.isNotEmpty) ...[
          const SizedBox(height: 4),
          // Sin recuadro: mismo tratamiento que la placa de la card
          // principal del viaje (`conductor_vehiculo_info.dart`) — texto
          // plano sobre `ink900`, que ya invierte solo con el tema
          // (near-negro en claro, near-blanco en oscuro). La versión con
          // caja necesitaba fijar dos colores a mano y en oscuro se leía
          // mal contra el fondo del sheet.
          Text(
            placa.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: context.palette.ink900,
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
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: context.palette.textPrimary,
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
      icono = const Icon(
        Icons.payments_rounded,
        color: AppColores.success,
        size: 22,
      );
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
      icono = const Icon(
        Icons.account_balance,
        color: AppColores.secondary,
        size: 22,
      );
      label = 'Transferencia';
    } else {
      icono = Icon(
        Icons.payment,
        color: context.palette.textSecondary,
        size: 22,
      );
      label = metodo.isEmpty ? '—' : metodo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icono,
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
