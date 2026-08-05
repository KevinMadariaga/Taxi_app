import 'package:flutter/widgets.dart';

/// Reparto responsivo info/mapa (`Expanded(flex:)`) para las pantallas de
/// viaje activo (conductor y cliente) — el 40/60 (o el que pase cada
/// pantalla) es para un teléfono "normal", pero ese % es contenido de alto
/// FIJO (avatar, filas de texto, botones): en una pantalla muy baja no
/// entra sin scrollear apretado, y en una tablet sobra tanto alto que se ve
/// como un hueco en blanco enorme debajo de los botones. Se ajusta el
/// reparto según el alto real en vez de dejar el % fijo en cualquier
/// dispositivo.
///
/// Base de referencia 390×844 (mismo diseño base que usa ScreenUtil en el
/// resto del proyecto, ver CLAUDE.md).
class InfoMapSplit {
  InfoMapSplit._();

  static const double _alturaBaja = 700;
  static const double _alturaAlta = 900;

  /// En pantalla baja, la card gana `_ajusteBajo` puntos porcentuales sobre
  /// [baseInfoFlex]; en pantalla alta, los pierde (`_ajusteAlto`) — mismo
  /// desplazamiento absoluto (±5) sin importar el % base que traiga cada
  /// pantalla.
  static const int _ajusteBajo = 5;
  static const int _ajusteAlto = 5;

  /// `(infoFlex, mapFlex)` según el alto real de pantalla (`MediaQuery`).
  /// [baseInfoFlex] es el % de info en un teléfono "normal" (700-900 de
  /// alto) — cada pantalla llamante define su propio balance base.
  static (int, int) forHeight(double screenHeight, {int baseInfoFlex = 40}) {
    final info = screenHeight < _alturaBaja
        ? baseInfoFlex + _ajusteBajo
        : screenHeight > _alturaAlta
        ? baseInfoFlex - _ajusteAlto
        : baseInfoFlex;
    return (info.clamp(20, 80), 100 - info.clamp(20, 80));
  }

  static (int, int) of(BuildContext context, {int baseInfoFlex = 40}) =>
      forHeight(MediaQuery.sizeOf(context).height, baseInfoFlex: baseInfoFlex);
}
