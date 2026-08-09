import 'package:flutter/widgets.dart';

/// Medidas de la tarjeta de viaje escaladas al alto real de pantalla.
///
/// El contenido de la tarjeta son píxeles fijos (avatar, foto del vehículo,
/// barra de progreso, botones), así que repartir la pantalla por porcentaje
/// fijo fallaba en los dos extremos: en teléfonos bajos el contenido no
/// entraba y aparecía scroll, y en pantallas altas sobraba aire dentro de la
/// tarjeta. Acá se escalan gaps y elementos gráficos por franja de alto; el
/// alto final de la tarjeta lo decide su propio contenido (ver
/// [alturaMaximaFactor] para el techo que sí depende de la pantalla).
@immutable
class TripCardMetrics {
  const TripCardMetrics._({
    required this.paddingVertical,
    required this.gapSuperior,
    required this.gapTitulo,
    required this.gapSeccion,
    required this.gapCompacto,
    required this.avatarRadius,
    required this.vehiculoWidth,
    required this.vehiculoHeight,
    required this.barraCircleSize,
    required this.alturaMaximaFactor,
  });

  /// Padding vertical del contenedor de la tarjeta.
  final double paddingVertical;

  /// Aire entre el borde superior seguro y el pill de título.
  final double gapSuperior;

  /// Aire entre el pill de título y el primer bloque de datos.
  final double gapTitulo;

  /// Separación entre bloques (banner ↔ conductor ↔ barra ↔ botones).
  final double gapSeccion;

  /// Separación corta dentro de un mismo bloque.
  final double gapCompacto;

  final double avatarRadius;
  final double vehiculoWidth;
  final double vehiculoHeight;
  final double barraCircleSize;

  /// Techo de alto de la tarjeta como fracción de la pantalla — evita que
  /// en un teléfono muy bajo la tarjeta se coma el mapa. Por debajo de ese
  /// techo la tarjeta mide lo que mide su contenido.
  final double alturaMaximaFactor;

  static const double _alturaBaja = 700;
  static const double _alturaAlta = 900;

  /// Pantalla baja (< 700): todo apretado, el mapa no puede desaparecer.
  static const TripCardMetrics compacta = TripCardMetrics._(
    paddingVertical: 10,
    gapSuperior: 4,
    gapTitulo: 10,
    gapSeccion: 8,
    gapCompacto: 6,
    avatarRadius: 30,
    vehiculoWidth: 72,
    vehiculoHeight: 52,
    barraCircleSize: 38,
    alturaMaximaFactor: 0.56,
  );

  /// Teléfono estándar (700-900): las medidas de referencia del diseño.
  static const TripCardMetrics normal = TripCardMetrics._(
    paddingVertical: 14,
    gapSuperior: 8,
    gapTitulo: 14,
    gapSeccion: 10,
    gapCompacto: 8,
    avatarRadius: 36,
    vehiculoWidth: 84,
    vehiculoHeight: 60,
    barraCircleSize: 44,
    alturaMaximaFactor: 0.52,
  );

  /// Pantalla alta o tablet (> 900): más aire, sin estirar la tarjeta a un
  /// porcentaje — el mapa se queda con lo que sobra.
  static const TripCardMetrics amplia = TripCardMetrics._(
    paddingVertical: 16,
    gapSuperior: 10,
    gapTitulo: 18,
    gapSeccion: 14,
    gapCompacto: 10,
    avatarRadius: 40,
    vehiculoWidth: 92,
    vehiculoHeight: 66,
    barraCircleSize: 48,
    alturaMaximaFactor: 0.48,
  );

  static TripCardMetrics forHeight(double screenHeight) {
    if (screenHeight < _alturaBaja) return compacta;
    if (screenHeight > _alturaAlta) return amplia;
    return normal;
  }

  static TripCardMetrics of(BuildContext context) =>
      forHeight(MediaQuery.sizeOf(context).height);
}
