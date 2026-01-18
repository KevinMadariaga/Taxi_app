import 'package:flutter/material.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/preview_solicitud.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PreviewSolicitudCard extends StatefulWidget {
  final PreviewSolicitud preview;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onCancel;
  final VoidCallback onAccept;

  const PreviewSolicitudCard({
    super.key,
    required this.preview,
    required this.isLoading,
    required this.onClose,
    required this.onCancel,
    required this.onAccept,
  });

  @override
  State<PreviewSolicitudCard> createState() => _PreviewSolicitudCardState();
}

class _PreviewSolicitudCardState extends State<PreviewSolicitudCard> {
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadClientPhoto();
  }

  Future<void> _loadClientPhoto() async {
    try {
      final clienteId = widget.preview.solicitud.clienteId;
      if (clienteId == null) return;
      final doc = await FirebaseFirestore.instance.collection('cliente').doc(clienteId).get();
      if (!doc.exists) return;
      final foto = doc.data()?['foto']?.toString() ?? doc.data()?['fotoUrl']?.toString() ?? doc.data()?['photo']?.toString();
      if (foto != null && foto.isNotEmpty) {
        if (mounted) setState(() => _photoUrl = foto);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final isLoading = widget.isLoading;
    final onClose = widget.onClose;
    final onCancel = widget.onCancel;
    final onAccept = widget.onAccept;

    final String cercania = (preview.distanciaKm != null)
      ? (preview.distanciaKm! <= 1.0 ? 'Cerca' : 'Lejos')
      : '—';

    return Card(
      margin: ResponsiveHelper.padding(context, all: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: ResponsiveHelper.padding(context, all: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.local_taxi, color: AppColores.textSecondary, size: ResponsiveHelper.sp(context, 18)),
                SizedBox(width: ResponsiveHelper.wp(context, 1.9)),
                Text(
                  'Solicitud seleccionada',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: ResponsiveHelper.sp(context, 16)),
                ),
                
              ],
            ),
            SizedBox(height: ResponsiveHelper.hp(context, 1.5)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _photoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(ResponsiveHelper.sp(context, 36)),
                            child: Image.network(
                              _photoUrl!,
                              width: ResponsiveHelper.sp(context, 50),
                              height: ResponsiveHelper.sp(context, 50),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, st) {
                                return Container(
                                  width: ResponsiveHelper.sp(context, 50),
                                  height: ResponsiveHelper.sp(context, 50),
                                  color: Colors.grey.shade200,
                                  child: Icon(Icons.person, color: Colors.grey.shade600, size: ResponsiveHelper.sp(context, 18)),
                                );
                              },
                            ),
                          )
                        : Container(
                            width: ResponsiveHelper.sp(context, 50),
                            height: ResponsiveHelper.sp(context, 50),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(ResponsiveHelper.sp(context, 30)),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.person, color: Colors.grey.shade600, size: ResponsiveHelper.sp(context, 18)),
                          ),
                    title: Text(
                      (preview.clientName ?? 'Cliente').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: ResponsiveHelper.sp(context, 15),
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Distancia',
                      style: TextStyle(fontSize: ResponsiveHelper.sp(context, 11), color: AppColores.textSecondary),
                    ),
                    Text(
                      cercania,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColores.textPrimary,
                        fontSize: ResponsiveHelper.sp(context, 13),
                      ),
                    ),
                  ],
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
                      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 3), vertical: ResponsiveHelper.hp(context, 0.2)),
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
                      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 3), vertical: ResponsiveHelper.hp(context, 0.2)),
                      child: Text(
                        'Pagará con:',
                        style: TextStyle(
                          fontSize: ResponsiveHelper.sp(context, 14),
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
                      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 3)),
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
                      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.wp(context, 3)),
                      child: Builder(builder: (context) {
                        final metodo = (preview.paymentMethod ?? '').toLowerCase();
                        IconData icon = Icons.payment;
                        if (metodo.contains('efectivo')) {
                          icon = Icons.attach_money;
                        } else if (metodo.contains('transfer')) {
                          icon = Icons.credit_card;
                        }
                        return Row(
                          children: [
                            Icon(icon, color: AppColores.primary, size: ResponsiveHelper.sp(context, 16)),
                            SizedBox(width: ResponsiveHelper.wp(context, 1.6)),
                            Expanded(
                              child: Text(
                                _formatMetodoPreview(preview.paymentMethod),
                                style: TextStyle(
                                  fontSize: ResponsiveHelper.sp(context, 14),
                                  color: AppColores.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.hp(context, 3)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomButton(
                  text: 'Cancelar',
                  color: Colors.white,
                  textColor: AppColores.buttonPrimary,
                  borderColor: AppColores.buttonPrimary,
                  onPressed: isLoading ? null : onCancel,
                  width: ResponsiveHelper.wp(context, 36),
                  height: ResponsiveHelper.hp(context, 6),
                  fontSize: ResponsiveHelper.sp(context, 14),
                ),
                SizedBox(width: ResponsiveHelper.wp(context, 3)),
                CustomButton(
                  text: 'Aceptar',
                  color: AppColores.buttonPrimary,
                  textColor: Colors.white,
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
    );
  }

  static String _formatMetodoPreview(String? metodo) {
    if (metodo == null || metodo.isEmpty) return '—';
    final lower = metodo.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}
