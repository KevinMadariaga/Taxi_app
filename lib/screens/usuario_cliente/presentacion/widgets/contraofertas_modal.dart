import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/buscando_taxi_viewmodel.dart'
    show BuscandoTaxiViewModel, ContraofertaItem;

// ─────────────────────────────────────────────────────────────────────────────
// ContraofertasModalContent
// Contenido del modal central que lista las contraofertas de conductores.
//
// Extraído de buscando_taxi_view.dart (comunidad de menor cohesión del repo
// según graphify-out/GRAPH_REPORT.md, 0.02) — la ORQUESTACIÓN del modal
// (cuándo abrirlo, guards de un solo disparo, cierre por Navigator del State)
// se queda en la View a propósito: usa el `context`/`mounted` del State, no
// del diálogo, para evitar un double-pop (ver comentario original en
// `_maybeMostrarModalContraofertas`). Este widget solo renderiza dado `vm` +
// callbacks, y avisa vía `onEmpty` cuando ya no quedan ofertas — la View
// decide cómo/cuándo cerrar.
// ─────────────────────────────────────────────────────────────────────────────

class ContraofertasModalContent extends StatelessWidget {
  const ContraofertasModalContent({
    super.key,
    required this.vm,
    required this.respondingOffer,
    required this.onAceptar,
    required this.onRechazar,
    required this.onEmpty,
  });

  final BuscandoTaxiViewModel vm;
  final Map<String, bool> respondingOffer;
  final void Function(String conductorId) onAceptar;
  final void Function(String conductorId) onRechazar;
  final VoidCallback onEmpty;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    return AnimatedBuilder(
      animation: vm,
      builder: (ctx, _) {
        final ofertas = vm.contraofertas;
        // Cuando ya no quedan ofertas (aceptada/rechazadas), avisar al padre
        // para que cierre el modal — con SU contexto, no el de este widget.
        if (ofertas.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onEmpty());
        }
        return Dialog(
          insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 40.h),
          backgroundColor: AppColores.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_taxi,
                        color: AppColores.primary,
                        size: 22,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'Conductores que ofertaron (${ofertas.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: isTablet ? 18 : 16,
                            color: AppColores.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Text(
                    'Elige la oferta que prefieras según valor y calificación.',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      color: AppColores.textSecondary,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: ofertas.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10.h),
                    itemBuilder: (_, i) {
                      final o = ofertas[i];
                      final isResponding =
                          respondingOffer[o.conductorId] == true ||
                          vm.isRespondingCounteroffer;
                      return _ContraofertaCard(
                        oferta: o,
                        isTablet: isTablet,
                        isResponding: isResponding,
                        onAceptar: () => onAceptar(o.conductorId),
                        onRechazar: () => onRechazar(o.conductorId),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ContraofertaCard extends StatelessWidget {
  const _ContraofertaCard({
    required this.oferta,
    required this.isTablet,
    required this.isResponding,
    required this.onAceptar,
    required this.onRechazar,
  });

  final ContraofertaItem oferta;
  final bool isTablet;
  final bool isResponding;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    final o = oferta;
    final hasPhoto = o.conductorFoto != null && o.conductorFoto!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColores.cardBackground,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColores.buttonPrimary, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: isTablet ? 26 : 22,
                  backgroundColor: AppColores.grey200,
                  backgroundImage: hasPhoto
                      ? NetworkImage(o.conductorFoto!)
                      : null,
                  child: !hasPhoto
                      ? Icon(
                          Icons.person,
                          size: isTablet ? 28 : 24,
                          color: AppColores.textSecondary,
                        )
                      : null,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.conductorNombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 15 : 13,
                          color: AppColores.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (o.placa != null && o.placa!.isNotEmpty)
                        Text(
                          o.placa!,
                          style: TextStyle(
                            fontSize: isTablet ? 13 : 11,
                            color: AppColores.textSecondary,
                          ),
                        ),
                      SizedBox(height: 4.h),
                      _buildEstrellas(o.calificacion, o.totalCalificaciones),
                    ],
                  ),
                ),
                SizedBox(width: 10.w),
                Text(
                  '\$${_formatCurrency(o.valor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isTablet ? 19 : 17,
                    color: AppColores.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            // Botones debajo de la calificación, ocupando el ancho.
            Row(
              children: [
                Expanded(
                  child: _OfertaButton(
                    label: 'Rechazar',
                    color: AppColores.grey200,
                    textColor: AppColores.textSecondary,
                    isLoading: isResponding,
                    onTap: onRechazar,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _OfertaButton(
                    label: 'Aceptar',
                    color: AppColores.buttonPrimary,
                    textColor: AppColores.textWhite,
                    isLoading: isResponding,
                    onTap: onAceptar,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Estrellas de calificación del conductor (promedio 0-5).
Widget _buildEstrellas(double calif, int total) {
  if (total <= 0 && calif <= 0) {
    return Text(
      'Conductor nuevo',
      style: TextStyle(fontSize: 11.5.sp, color: AppColores.textSecondary),
    );
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ...List.generate(5, (i) {
        IconData icon;
        if (calif >= i + 1) {
          icon = Icons.star_rounded;
        } else if (calif >= i + 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: 15, color: AppColores.warning);
      }),
      SizedBox(width: 4.w),
      Text(
        '${calif.toStringAsFixed(1)} ($total)',
        style: TextStyle(
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w600,
          color: AppColores.textSecondary,
        ),
      ),
    ],
  );
}

String _formatCurrency(num value) {
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

// ─────────────────────────────────────────────────────────────────────────────
// _OfertaButton — botón de aceptar/rechazar con estado de carga
// ─────────────────────────────────────────────────────────────────────────────

class _OfertaButton extends StatelessWidget {
  const _OfertaButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sin spinner: solo se atenúa y se deshabilita mientras procesa, para
    // evitar doble toque. La confirmación visual la da la pantalla
    // "Conductor encontrado" al aceptar.
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: isLoading ? 0.6 : 1.0,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
