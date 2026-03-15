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

  const PreviewSolicitudCard({
    super.key,
    required this.preview,
    this.clientPhotoUrl,
    required this.isLoading,
    required this.onClose,
    required this.onCancel,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    final isLoading = this.isLoading;
    final onCancel = this.onCancel;
    final onAccept = this.onAccept;

    final double avatarSize = ResponsiveHelper.sp(context, 70);

    final String cercania = (preview.distanciaKm != null)
        ? (preview.distanciaKm! <= 1.0 ? 'Cerca' : 'Lejos')
        : '—';

    return Padding(
      // Asegura que respetamos notch, barras de sistema y gestos
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          // Altura útil descontando las zonas seguras del sistema
          final usableHeight = media.size.height - media.padding.vertical;

          // Limitamos la altura para que en pantallas pequeñas no se corte
          final maxHeight = constraints.maxHeight == double.infinity
              ? usableHeight * 0.6
              : constraints.maxHeight.clamp(0.0, usableHeight * 0.9);

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Container(
              color: AppColores.cardBackground,
              // Menos padding lateral y superior para que la foto se vea más protagonista
              padding: ResponsiveHelper.padding(
                context,
                top: 12,
                left: 14,
                right: 14,
                bottom: 0,
              ),
              child: SingleChildScrollView(
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
                            SizedBox(width: ResponsiveHelper.wp(context, 2.5)),
                            Text(
                              'Solicitud seleccionada',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: ResponsiveHelper.sp(context, 17),
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
                    SizedBox(height: ResponsiveHelper.hp(context, 2)),
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
                                      clientPhotoUrl != null &&
                                          clientPhotoUrl!.isNotEmpty
                                      ? NetworkImage(clientPhotoUrl!)
                                      : null,
                                  child:
                                      (clientPhotoUrl == null ||
                                          clientPhotoUrl!.isEmpty)
                                      ? Icon(
                                          Icons.person,
                                          color: AppColores.textWhite,
                                          size: ResponsiveHelper.sp(
                                            context,
                                            25,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.wp(context, 2)),
                              Expanded(
                                child: Text(
                                  (preview.clientName ?? 'Cliente')
                                      .toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: ResponsiveHelper.sp(context, 15),
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
                                  fontSize: ResponsiveHelper.sp(context, 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.hp(context, 2)),
                    // Show origin (recoger) and client location side-by-side using a Table
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(0.8),
                      },
                      children: [
                        TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.wp(context, 1),
                                vertical: ResponsiveHelper.hp(context, 0.1),
                              ),
                              child: Text(
                                'Recoger en:',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 14),
                                  color: AppColores.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: ResponsiveHelper.wp(context, 5),
                                right: ResponsiveHelper.wp(context, 2),
                                top: ResponsiveHelper.hp(context, 0.1),
                                bottom: ResponsiveHelper.hp(context, 0.1),
                              ),
                              child: Text(
                                'Pagará con:',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 12),
                                  color: AppColores.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.wp(context, 1),
                              ),
                              child: Text(
                                preview.solicitud.origenTitle ??
                                    '${preview.solicitud.ubicacionInicial.latitude.toStringAsFixed(5)}, ${preview.solicitud.ubicacionInicial.longitude.toStringAsFixed(5)}',
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 13),
                                  color: AppColores.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(
                                left: ResponsiveHelper.wp(context, 4),
                                right: 0,
                                top: ResponsiveHelper.hp(context, 0.1),
                                bottom: ResponsiveHelper.hp(context, 0.1),
                              ),
                              child: Builder(
                                builder: (context) {
                                  final metodo = (preview.paymentMethod ?? '')
                                      .toLowerCase();
                                  IconData icon = Icons.payment;
                                  if (metodo.contains('efectivo')) {
                                    icon = Icons.attach_money;
                                  } else if (metodo.contains('transfer')) {
                                    icon = Icons.credit_card;
                                  }
                                  return Row(
                                    children: [
                                      Icon(
                                        icon,
                                        color: AppColores.primary,
                                        size: ResponsiveHelper.sp(context, 16),
                                      ),
                                      SizedBox(width: 3),
                                      Flexible(
                                        fit: FlexFit.tight,
                                        child: Align(
                                          alignment: Alignment.centerRight,
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
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.hp(context, 2)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomButton(
                          text: 'Cancelar',
                          color: AppColores.surface,
                          textColor: AppColores.buttonPrimary,
                          borderColor: AppColores.buttonPrimary,
                          onPressed: isLoading ? null : onCancel,
                          width: ResponsiveHelper.wp(context, 36),
                          height: ResponsiveHelper.hp(context, 6),
                          fontSize: ResponsiveHelper.sp(context, 14),
                        ),
                        SizedBox(width: ResponsiveHelper.wp(context, 4)),
                        CustomButton(
                          text: 'Aceptar',
                          color: AppColores.buttonPrimary,
                          textColor: AppColores.textWhite,
                          isLoading: isLoading,
                          onPressed: isLoading ? null : onAccept,
                          width: ResponsiveHelper.wp(context, 36),
                          height: ResponsiveHelper.hp(context, 6),
                          fontSize: ResponsiveHelper.sp(context, 14),
                        ),
                      ],
                    ),
                  ],
                ),
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
}
