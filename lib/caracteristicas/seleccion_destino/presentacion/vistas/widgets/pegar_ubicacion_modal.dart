import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/widgets/boton.dart';

import '../../viewmodels/seleccion_destino_viewmodel.dart';
import '../seleccionar_ubicacion_mapa_view.dart';

/// Flujo "Pegar ubicación": modal "Pega tu ubicación" → lee portapapeles →
/// parsea coordenadas → abre el mapa movible centrado ahí para confirmar.
///
/// Devuelve el resultado confirmado (posición + dirección) para que el
/// caller llene el campo destino, o `null` si se canceló en cualquier paso.
Future<SeleccionUbicacionResult?> mostrarPegarUbicacionModal(
  BuildContext context, {
  required SeleccionDestinoViewModel vm,
}) async {
  final posicion = await showModalBottomSheet<LatLng>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (ctx) => _PegarUbicacionSheet(vm: vm),
  );
  if (posicion == null || !context.mounted) return null;

  return Navigator.of(context).push<SeleccionUbicacionResult>(
    MaterialPageRoute(
      builder: (_) => SeleccionarUbicacionMapaView(
        ubicacionInicial: posicion,
        titulo: 'Confirma la ubicación pegada',
      ),
    ),
  );
}

class _PegarUbicacionSheet extends StatefulWidget {
  const _PegarUbicacionSheet({required this.vm});

  final SeleccionDestinoViewModel vm;

  @override
  State<_PegarUbicacionSheet> createState() => _PegarUbicacionSheetState();
}

class _PegarUbicacionSheetState extends State<_PegarUbicacionSheet> {
  bool _buscando = false;
  String? _error;

  Future<void> _pegar() async {
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final texto = data?.text?.trim() ?? '';
      if (texto.isEmpty) {
        setState(() {
          _buscando = false;
          _error = 'No hay texto en el portapapeles.';
        });
        return;
      }
      final posicion = await widget.vm.extraerUbicacionDesdeTexto(texto);
      if (!mounted) return;
      if (posicion == null) {
        setState(() {
          _buscando = false;
          _error = 'No se encontraron coordenadas en el texto pegado.';
        });
        return;
      }
      Navigator.of(context).pop(posicion);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = 'No se pudo leer la ubicación pegada.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColores.grey300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              'Pega tu ubicación',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: AppColores.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Copia un link de Google Maps o unas coordenadas y tocá pegar.',
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColores.textSecondary,
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 12.h),
              Text(
                _error!,
                style: TextStyle(fontSize: 13.sp, color: AppColores.error),
              ),
            ],
            SizedBox(height: 20.h),
            CustomButton(
              text: 'Pegar',
              width: double.infinity,
              height: 52.h,
              isLoading: _buscando,
              icon: const Icon(
                Icons.content_paste_rounded,
                size: 18,
                color: AppColores.textWhite,
              ),
              onPressed: _pegar,
            ),
          ],
        ),
      ),
    );
  }
}
