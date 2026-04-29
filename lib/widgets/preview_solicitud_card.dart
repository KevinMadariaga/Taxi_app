import 'package:flutter/material.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';

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
    final preview = this.preview;
    final isLoading = this.isLoading;
    final photoUrl = this.clientPhotoUrl ?? preview.clientPhotoUrl;
    final onAccept = this.onAccept;
    final onCounterOffer = this.onCounterOffer;

    final String cercania = (preview.distanciaKm != null)
        ? (preview.distanciaKm! <= 1.0 ? 'Cerca' : 'Lejos')
        : '—';
    final comentario = _normalizeComment(preview.comentarioCliente);
    final hasComentario = comentario != null;
    final valorCliente = preview.valorServicio;
    final valorContra = preview.valorContraoferta;

    return Padding(
      // Asegura que respetamos notch, barras de sistema y gestos
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 380;
          final avatarSize = isCompact
              ? ResponsiveHelper.sp(context, 56)
              : ResponsiveHelper.sp(context, 70);
          final sectionGap = isCompact ? 1.2 : 2.0;
          final buttonHeight = isCompact
              ? ResponsiveHelper.hp(context, 4.7)
              : ResponsiveHelper.hp(context, 5.0);
          final buttonWidth = isCompact
              ? constraints.maxWidth * 0.41
              : constraints.maxWidth * 0.40;

          final media = MediaQuery.of(context);
          // Altura útil descontando las zonas seguras del sistema
          final usableHeight = media.size.height - media.padding.vertical;

          // Limitamos la altura para que en pantallas pequeñas no se corte
            final maxHeight = constraints.maxHeight == double.infinity
              ? usableHeight * 0.95
              : constraints.maxHeight.clamp(0.0, usableHeight * 0.95);

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColores.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColores.borderSubtle),
              ),
              // Menos padding lateral y superior para que la foto se vea más protagonista
              padding: ResponsiveHelper.padding(
                context,
                top: isCompact ? 10 : 12,
                left: isCompact ? 12 : 14,
                right: isCompact ? 12 : 14,
                bottom: isCompact ? 10 : 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.local_taxi,
                                color: AppColores.textSecondary,
                                size: ResponsiveHelper.sp(context, 20),
                              ),
                              SizedBox(
                                width: ResponsiveHelper.wp(context, 2.5),
                              ),
                              Text(
                                'Solicitud seleccionada',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: ResponsiveHelper.sp(
                                    context,
                                    isCompact ? 15 : 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: onClose,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColores.grey200,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                color: AppColores.textSecondary,
                                size: ResponsiveHelper.sp(context, 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: ResponsiveHelper.hp(context, sectionGap),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: avatarSize,
                                  height: avatarSize,
                                  child: CircleAvatar(
                                    radius: avatarSize / 2,
                                    backgroundColor: AppColores.grey400,
                                    backgroundImage:
                                        photoUrl != null && photoUrl.isNotEmpty
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child:
                                        (photoUrl == null || photoUrl.isEmpty)
                                        ? Icon(
                                            Icons.person,
                                            color: AppColores.textWhite,
                                            size: ResponsiveHelper.sp(
                                              context,
                                              isCompact ? 22 : 25,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                SizedBox(
                                  width: ResponsiveHelper.wp(context, 2),
                                ),
                                Expanded(
                                  child: Text(
                                    (preview.clientName ?? 'Cliente')
                                        .toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: ResponsiveHelper.sp(
                                        context,
                                        isCompact ? 14 : 15,
                                      ),
                                      color: AppColores.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              left: ResponsiveHelper.wp(context, 2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Distancia',
                                  style: TextStyle(
                                    fontSize: ResponsiveHelper.sp(context, 14),
                                    color: AppColores.textSecondary,
                                  ),
                                ),
                                Text(
                                  cercania,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColores.textPrimary,
                                    fontSize: ResponsiveHelper.sp(
                                      context,
                                      isCompact ? 15 : 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: ResponsiveHelper.hp(context, sectionGap),
                      ),
                      if (isCompact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoBlock(
                              label: 'Recoger en:',
                              child: Text(
                                _pickupText(preview),
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 13),
                                  color: AppColores.textPrimary,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.hp(context, 0.9)),
                            _InfoBlock(
                              label: 'Pagará con:',
                              child: Row(
                                children: [
                                  Icon(
                                    _paymentIcon(preview.paymentMethod),
                                    color: AppColores.primary,
                                    size: ResponsiveHelper.sp(context, 16),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _formatMetodoPreview(
                                        preview.paymentMethod,
                                      ),
                                      style: TextStyle(
                                        fontSize: ResponsiveHelper.sp(
                                          context,
                                          14,
                                        ),
                                        color: AppColores.textPrimary,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _InfoBlock(
                                label: 'Recoger en:',
                                child: Text(
                                  _pickupText(preview),
                                  style: TextStyle(
                                    fontSize: ResponsiveHelper.sp(context, 13),
                                    color: AppColores.textPrimary,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.wp(context, 4)),
                            Expanded(
                              child: _InfoBlock(
                                label: 'Pagará con:',
                                alignEnd: true,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Icon(
                                      _paymentIcon(preview.paymentMethod),
                                      color: AppColores.primary,
                                      size: ResponsiveHelper.sp(context, 16),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _formatMetodoPreview(
                                          preview.paymentMethod,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: ResponsiveHelper.sp(
                                            context,
                                            14,
                                          ),
                                          color: AppColores.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(
                        height: ResponsiveHelper.hp(context, sectionGap),
                      ),
                      if (hasComentario) ...[
                        SizedBox(height: ResponsiveHelper.hp(context, 1.2)),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.wp(context, 2.5),
                            vertical: ResponsiveHelper.hp(context, 0.9),
                          ),
                          decoration: BoxDecoration(
                            color: AppColores.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColores.borderSubtle),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: ResponsiveHelper.sp(context, 15),
                                color: AppColores.textSecondary,
                              ),
                              SizedBox(width: ResponsiveHelper.wp(context, 2)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Comentario del cliente',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: ResponsiveHelper.sp(
                                          context,
                                          12,
                                        ),
                                        color: AppColores.textPrimary,
                                      ),
                                    ),
                                    SizedBox(
                                      height: ResponsiveHelper.hp(context, 0.2),
                                    ),
                                    Text(
                                      comentario,
                                      maxLines: isCompact ? 3 : 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: ResponsiveHelper.sp(
                                          context,
                                          12.5,
                                        ),
                                        color: AppColores.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 1.8)),
                      ] else ...[
                        SizedBox(height: ResponsiveHelper.hp(context, 0.1)),
                      ],
                      if (valorCliente != null) ...[
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.wp(context, 2.5),
                            vertical: ResponsiveHelper.hp(context, 0.9),
                          ),
                          decoration: BoxDecoration(
                            color: AppColores.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColores.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Oferta del cliente',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: ResponsiveHelper.sp(
                                              context,
                                              14,
                                            ),
                                            color: AppColores.textPrimary,
                                          ),
                                        ),
                                        if (valorContra != null) ...[
                                          SizedBox(
                                            height: ResponsiveHelper.hp(
                                              context,
                                              0.35,
                                            ),
                                          ),
                                          Text(
                                            'Contraoferta hecha',
                                            style: TextStyle(
                                              fontSize: ResponsiveHelper.sp(
                                                context,
                                                12,
                                              ),
                                              color: AppColores.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(
                                            height: ResponsiveHelper.hp(
                                              context,
                                              0.15,
                                            ),
                                          ),
                                          Text(
                                            '\$${_formatCurrency(valorContra)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: ResponsiveHelper.sp(
                                                context,
                                                13,
                                              ),
                                              color: AppColores.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '\$${_formatCurrency(valorCliente)}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: ResponsiveHelper.sp(
                                        context,
                                        16,
                                      ),
                                      color: AppColores.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.hp(context, 0.6)),
                      ],
                      Wrap(
                        spacing: ResponsiveHelper.wp(context, 2.3),
                        runSpacing: ResponsiveHelper.hp(context, 0.4),
                        alignment: WrapAlignment.center,
                        children: [
                          CustomButton(
                            text: 'Ofertar',
                            color: AppColores.surface,
                            textColor: AppColores.buttonPrimary,
                            borderColor: AppColores.buttonPrimary,
                            isLoading: isLoading,
                            onPressed: isLoading ? null : onCounterOffer,
                            width: buttonWidth,
                            height: buttonHeight,
                            fontSize: ResponsiveHelper.sp(context, 14),
                          ),
                          CustomButton(
                            text: 'Aceptar',
                            color: AppColores.buttonPrimary,
                            textColor: AppColores.textWhite,
                            onPressed: isLoading ? null : onAccept,
                            width: buttonWidth,
                            height: buttonHeight,
                            fontSize: ResponsiveHelper.sp(context, 14),
                          ),
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.hp(context, 0.2)),
                ],
              ),
            ),
          );
        },
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

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
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
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: ResponsiveHelper.sp(context, 13),
            color: AppColores.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.hp(context, 0.2)),
        child,
      ],
    );
  }
}
