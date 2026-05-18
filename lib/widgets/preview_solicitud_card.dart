import 'package:flutter/material.dart';
import 'package:taxi_app/widgets/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodels/preview_solicitud.dart';

class PreviewSolicitudCard extends StatelessWidget {
  final PreviewSolicitud preview;
  final String? clientPhotoUrl;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onCounterOffer;

  const PreviewSolicitudCard({
    super.key,
    required this.preview,
    this.clientPhotoUrl,
    required this.isLoading,
    required this.onClose,
    required this.onCancel,
    required this.onAccept,
    required this.onCounterOffer,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = clientPhotoUrl ?? preview.clientPhotoUrl;
    final comentario = _normalizeComment(preview.comentarioCliente);
    final hasComentario = comentario != null;
    final valorCliente = preview.valorServicio;
    final valorContra = preview.valorContraoferta;

    final km = preview.distanciaKm;
    final String cercania;
    final Color badgeColor;
    final Color badgeTextColor;
    if (km != null && km <= 1.0) {
      cercania = 'Cerca';
      badgeColor = AppColores.success.withValues(alpha: 0.12);
      badgeTextColor = AppColores.success;
    } else if (km != null) {
      cercania = 'Lejos';
      badgeColor = AppColores.warning.withValues(alpha: 0.12);
      badgeTextColor = AppColores.warning;
    } else {
      cercania = '—';
      badgeColor = AppColores.grey200;
      badgeTextColor = AppColores.textSecondary;
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DragHandle(),
              // Header: ícono + título + cerrar
              Row(
                children: [
                  const Icon(
                    Icons.local_taxi,
                    color: AppColores.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Solicitud seleccionada',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColores.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: AppColores.grey200,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColores.textSecondary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Sección cliente: avatar + nombre + badge de distancia
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColores.grey400,
                    backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? const Icon(
                            Icons.person,
                            color: AppColores.textWhite,
                            size: 28,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (preview.clientName ?? 'Cliente').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColores.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            cercania,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColores.borderSubtle, height: 1),
              const SizedBox(height: 14),
              // Fila de info: origen | divider | pago
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _InfoColumn(
                        label: 'Recoger en',
                        child: Text(
                          _pickupText(preview),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(
                      color: AppColores.borderSubtle,
                      width: 24,
                      thickness: 1,
                    ),
                    Expanded(
                      child: _InfoColumn(
                        label: 'Pagará con',
                        alignEnd: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(
                              _paymentIcon(preview.paymentMethod),
                              color: AppColores.primary,
                              size: 15,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _formatMetodoPreview(preview.paymentMethod),
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Comentario del cliente
              if (hasComentario) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColores.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColores.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 15,
                        color: AppColores.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Comentario del cliente',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColores.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              comentario,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColores.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Bloque de precio
              if (valorCliente != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColores.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColores.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Oferta del cliente',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColores.textPrimary,
                              ),
                            ),
                            if (valorContra != null) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'Contraoferta hecha',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColores.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '\$${_formatCurrency(valorContra)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColores.textPrimary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        '\$${_formatCurrency(valorCliente)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: AppColores.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // Botones de acción
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: 'Ofertar',
                      color: AppColores.surface,
                      textColor: AppColores.buttonPrimary,
                      borderColor: AppColores.buttonPrimary,
                      isLoading: isLoading,
                      onPressed: isLoading ? null : onCounterOffer,
                      width: double.infinity,
                      height: 48,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CustomButton(
                      text: 'Aceptar',
                      color: AppColores.buttonPrimary,
                      textColor: AppColores.textWhite,
                      isLoading: isLoading,
                      onPressed: isLoading ? null : onAccept,
                      width: double.infinity,
                      height: 48,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMetodoPreview(String? metodo) {
    if (metodo == null || metodo.isEmpty) return '—';
    final lower = metodo.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  static IconData _paymentIcon(String? metodo) {
    final lower = (metodo ?? '').toLowerCase();
    if (lower.contains('efectivo')) return Icons.attach_money;
    if (lower.contains('transfer') || lower.contains('nequi')) {
      return Icons.credit_card;
    }
    return Icons.payment;
  }

  static String _pickupText(PreviewSolicitud preview) {
    final title = preview.solicitud.origenTitle?.trim();
    if (title != null && title.isNotEmpty) return title;

    final address = preview.solicitud.direccion?.trim();
    if (address != null && address.isNotEmpty) return address;

    final lat = preview.solicitud.ubicacionInicial.latitude.toStringAsFixed(5);
    final lng = preview.solicitud.ubicacionInicial.longitude.toStringAsFixed(5);
    return '$lat, $lng';
  }

  static String _formatCurrency(num value) {
    final asInt = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < asInt.length; i++) {
      final reverseIndex = asInt.length - i;
      buf.write(asInt[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buf.write('.');
      }
    }
    return buf.toString();
  }

  static String? _normalizeComment(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'null' ||
        lower == 'ninguno' ||
        lower == 'sin comentario' ||
        lower == 'n/a' ||
        lower == 'na' ||
        text == '-') {
      return null;
    }
    return text;
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColores.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({
    required this.label,
    required this.child,
    this.alignEnd = false,
  });

  final String label;
  final Widget child;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(
            fontSize: 12,
            color: AppColores.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        child,
      ],
    );
  }
}
