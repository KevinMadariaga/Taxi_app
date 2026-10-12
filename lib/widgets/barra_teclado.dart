import 'package:flutter/material.dart';
import 'package:taxi_app/core/theme/app_palette.dart';

/// Barra "Listo" pegada encima del teclado, en toda la app: cierra el
/// teclado desde cualquier campo, también los numéricos y de teléfono del
/// iPhone, que no traen tecla para hacerlo.
///
/// Para no tapar nada, suma su alto al del teclado (`viewInsets`): los
/// Scaffold y las hojas que ya se corren por el teclado quedan también por
/// encima de la barra. El árbol tiene la misma forma con y sin teclado, así
/// no se pierde el estado de la navegación al abrirlo o cerrarlo.
class BarraTeclado extends StatelessWidget {
  const BarraTeclado({super.key, required this.child});

  final Widget child;

  static const double alto = 44;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final teclado = mq.viewInsets.bottom;
    final visible = teclado > 0;
    return Stack(
      children: [
        MediaQuery(
          data: visible
              ? mq.copyWith(
                  viewInsets: mq.viewInsets.copyWith(bottom: teclado + alto),
                )
              : mq,
          child: child,
        ),
        if (visible)
          Positioned(
            left: 0,
            right: 0,
            bottom: teclado,
            height: alto,
            child: const _Barra(),
          ),
      ],
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.borderSubtle)),
        ),
        child: Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              icon: const Icon(Icons.keyboard_hide_rounded),
              label: const Text(
                'Listo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
