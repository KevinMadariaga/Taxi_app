import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/features/trip_tracking_cliente/services/trip_tracking_firestore_service.dart';

/// Permite al cliente revisar y modificar el método de pago del viaje.
/// Actualiza el campo `paymentMethod` del documento `solicitudes/{id}`.
class MetodoPagoView extends StatefulWidget {
  const MetodoPagoView({
    super.key,
    required this.solicitudId,
    this.metodoActual = '',
  });

  final String solicitudId;
  final String metodoActual;

  @override
  State<MetodoPagoView> createState() => _MetodoPagoViewState();
}

class _MetodoPagoViewState extends State<MetodoPagoView> {
  static const List<_OpcionPago> _opciones = [
    _OpcionPago('Efectivo', Icons.payments_rounded, null),
    _OpcionPago('Nequi', null, 'assets/img/nequi.png'),
    _OpcionPago('Transferencia', Icons.account_balance, null),
  ];

  String _seleccion = '';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _seleccion = _normalizar(widget.metodoActual);
  }

  String _normalizar(String metodo) {
    final m = metodo.toLowerCase();
    if (m.contains('efectivo') || m.contains('cash')) return 'Efectivo';
    if (m.contains('nequi')) return 'Nequi';
    if (m.contains('transfer') || m.contains('banco')) return 'Transferencia';
    return '';
  }

  Future<void> _guardar() async {
    if (_seleccion.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    try {
      await TripTrackingFirebaseService().actualizarMetodoPago(
        solicitudId: widget.solicitudId,
        metodo: _seleccion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Método de pago actualizado')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColores.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColores.textPrimary,
        elevation: 0,
        title: const Text(
          'Método de pago',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                const Text(
                  '¿Cómo deseas pagar tu viaje?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColores.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                ..._opciones.map((o) {
                  final sel = _seleccion == o.label;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _seleccion = o.label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColores.buttonPrimary.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: sel
                                ? AppColores.buttonPrimary
                                : AppColores.borderSubtle,
                            width: sel ? 1.6 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: o.asset != null
                                    ? Colors.white
                                    : AppColores.secondary.withValues(
                                        alpha: 0.12,
                                      ),
                                shape: BoxShape.circle,
                                border: o.asset != null
                                    ? Border.all(color: AppColores.borderSubtle)
                                    : null,
                              ),
                              child: o.asset != null
                                  ? Image.asset(
                                      o.asset!,
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.account_balance_wallet,
                                        color: AppColores.secondary,
                                        size: 22,
                                      ),
                                    )
                                  : Icon(
                                      o.icon,
                                      color: AppColores.secondary,
                                      size: 22,
                                    ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                o.label,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                            Icon(
                              sel
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: sel
                                  ? AppColores.buttonPrimary
                                  : AppColores.grey400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_seleccion.isEmpty || _guardando)
                      ? null
                      : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColores.buttonPrimary,
                    foregroundColor: AppColores.textWhite,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColores.textWhite,
                          ),
                        )
                      : const Text(
                          'Guardar método de pago',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpcionPago {
  const _OpcionPago(this.label, this.icon, this.asset);
  final String label;
  final IconData? icon;
  final String? asset;
}
