import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taxi_app/core/theme/app_palette.dart';
import 'package:taxi_app/widgets/ajustes_ui.dart';

import '../../dominio/entidades/estadistica_dia.dart';

/// Colores de los resultados de una solicitud. Paleta validada (claro y
/// oscuro: contraste, croma y separación para daltonismo) en el orden en
/// que se apilan, que es el que mantiene separados los pares parecidos
/// (rojo y ámbar nunca quedan juntos). Siempre van con su etiqueta.
abstract final class ColoresResultado {
  static const completadas = Color(0xFF1F6FD1);
  static const sinRespuesta = Color(0xFFB86E00);
  static const enCurso = Color(0xFF0E9488);
  static const canceladas = Color(0xFFD93A3A);

  static const leyenda = [
    ('Completadas', completadas),
    ('Sin respuesta', sinRespuesta),
    ('En curso', enCurso),
    ('Canceladas', canceladas),
  ];
}

/// Tope "redondo" del eje (1, 2, 5 × 10ⁿ) para que las líneas guía caigan
/// en números fáciles de leer.
int topeRedondo(int maximo) {
  if (maximo <= 4) return 4;
  final p = math.pow(10, (math.log(maximo) / math.ln10).floor()).toInt();
  for (final m in [1, 2, 5, 10]) {
    if (m * p >= maximo) return m * p;
  }
  return 10 * p;
}

class Leyenda extends StatelessWidget {
  const Leyenda({super.key, required this.items});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (texto, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Eje Y con líneas guía recesivas y la etiqueta de cada una, y el área de
/// las barras encima. Compartido por las dos gráficas.
class _MarcoGrafica extends StatelessWidget {
  const _MarcoGrafica({
    required this.tope,
    required this.barras,
    required this.etiquetasX,
  });

  final int tope;
  final Widget barras;
  final Widget etiquetasX;

  static const double alto = 170;
  static const double anchoEje = 30;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final estiloEje = TextStyle(fontSize: 11, color: palette.textSecondary);
    return Column(
      children: [
        SizedBox(
          height: alto,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: anchoEje,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$tope', style: estiloEje),
                    Text('${tope ~/ 2}', style: estiloEje),
                    Text('0', style: estiloEje),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Stack(
                  children: [
                    for (final f in [0.0, 0.5, 1.0])
                      Positioned(
                        left: 0,
                        right: 0,
                        top: (alto - 1) * f,
                        child: Container(
                          height: 1,
                          color: palette.borderSubtle.withValues(
                            alpha: f == 1.0 ? 1 : 0.6,
                          ),
                        ),
                      ),
                    Positioned.fill(child: barras),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: anchoEje + 6),
          child: etiquetasX,
        ),
      ],
    );
  }
}

/// Etiquetas del eje X sin chocar: muestra una de cada [cada].
class _EtiquetasX extends StatelessWidget {
  const _EtiquetasX({required this.textos, required this.cada});

  final List<String> textos;
  final int cada;

  @override
  Widget build(BuildContext context) {
    final estilo = TextStyle(
      fontSize: 11,
      color: context.palette.textSecondary,
    );
    return Row(
      children: [
        for (var i = 0; i < textos.length; i++)
          Expanded(
            child: Text(
              i % cada == 0 || i == textos.length - 1 ? textos[i] : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: estilo,
            ),
          ),
      ],
    );
  }
}

/// Barras apiladas por día con el resultado de las solicitudes creadas
/// ese día. Tocar una barra elige el día ([onSeleccionar]).
class GraficaResultadosPorDia extends StatelessWidget {
  const GraficaResultadosPorDia({
    super.key,
    required this.dias,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final List<EstadisticaDia> dias;
  final int seleccionado;
  final ValueChanged<int> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final tope = topeRedondo(dias.fold(0, (m, d) => math.max(m, d.creadas)));
    return _MarcoGrafica(
      tope: tope,
      barras: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < dias.length; i++)
            Expanded(
              child: _ColumnaDia(
                dia: dias[i],
                tope: tope,
                seleccionada: i == seleccionado,
                onTap: () => onSeleccionar(i),
              ),
            ),
        ],
      ),
      etiquetasX: _EtiquetasX(
        textos: [for (final d in dias) '${d.dia.day}'],
        cada: (dias.length / 8).ceil(),
      ),
    );
  }
}

class _ColumnaDia extends StatelessWidget {
  const _ColumnaDia({
    required this.dia,
    required this.tope,
    required this.seleccionada,
    required this.onTap,
  });

  final EstadisticaDia dia;
  final int tope;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // De abajo hacia arriba, en el orden de la leyenda.
    final segmentos = [
      (dia.completadas, ColoresResultado.completadas),
      (dia.sinRespuesta, ColoresResultado.sinRespuesta),
      (dia.enCurso, ColoresResultado.enCurso),
      (dia.canceladas, ColoresResultado.canceladas),
    ].where((s) => s.$1 > 0).toList();
    return Semantics(
      button: true,
      selected: seleccionada,
      label:
          '${dia.dia.day}/${dia.dia.month}: ${dia.creadas} creadas, '
          '${dia.completadas} completadas, ${dia.canceladas} canceladas',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: seleccionada
                ? acentoMarca(context).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final ancho = math.min(c.maxWidth * 0.62, 26.0);
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var k = segmentos.length - 1; k >= 0; k--) ...[
                    Container(
                      width: ancho,
                      // Los separadores de 2 px salen del alto disponible:
                      // la suma nunca pasa del área de la gráfica.
                      height:
                          (c.maxHeight - 2 * (segmentos.length - 1)) *
                          segmentos[k].$1 /
                          tope,
                      decoration: BoxDecoration(
                        color: segmentos[k].$2,
                        borderRadius: k == segmentos.length - 1
                            ? const BorderRadius.vertical(
                                top: Radius.circular(4),
                              )
                            : null,
                      ),
                    ),
                    if (k > 0) SizedBox(height: 2, width: ancho),
                  ],
                  if (segmentos.isEmpty)
                    Container(width: ancho, height: 1, color: palette.grey300),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Solicitudes creadas por hora en un día: muestra las horas pico.
class GraficaPorHora extends StatelessWidget {
  const GraficaPorHora({super.key, required this.dia});

  final EstadisticaDia dia;

  @override
  Widget build(BuildContext context) {
    final valores = [for (var h = 0; h < 24; h++) dia.horaDe(h)];
    final tope = topeRedondo(valores.fold(0, math.max));
    final color = acentoMarca(context);
    return _MarcoGrafica(
      tope: tope,
      barras: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message:
                    '${h.toString().padLeft(2, '0')}:00 · ${valores[h]} '
                    '${valores[h] == 1 ? 'solicitud' : 'solicitudes'}',
                child: LayoutBuilder(
                  builder: (context, c) => Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: math.min(c.maxWidth * 0.62, 14),
                      height: math.max(1, c.maxHeight * valores[h] / tope),
                      decoration: BoxDecoration(
                        color: valores[h] == 0
                            ? context.palette.grey300
                            : color,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      etiquetasX: _EtiquetasX(
        textos: [for (var h = 0; h < 24; h++) '${h}h'],
        cada: 6,
      ),
    );
  }
}
