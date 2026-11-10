import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Lo mínimo de un conductor conectado para saber si está disponible cerca.
@immutable
class ConductorPresente {
  const ConductorPresente({
    required this.lat,
    required this.lng,
    required this.esMoto,
    required this.visto,
  });

  final double lat;
  final double lng;
  final bool esMoto;

  /// Última señal de vida (`conductores_conectados/{uid}.updatedAt`).
  final DateTime visto;
}

/// Conductores activos cerca de un punto de recogida, por tipo de vehículo.
@immutable
class DisponibilidadConductores {
  const DisponibilidadConductores({
    this.carros = 0,
    this.motos = 0,
    this.metrosCarroMasCercano,
    this.metrosMotoMasCercana,
  });

  final int carros;
  final int motos;
  final double? metrosCarroMasCercano;
  final double? metrosMotoMasCercana;
}

/// Mismo radio con el que el servidor reparte la solicitud
/// (`repartirSolicitud` en functions/index.js).
const double radioBusquedaMetros = 3000;

/// El conductor conectado late cada 2 min: 5 tolera un latido perdido sin
/// contar a alguien que ya se fue.
const Duration ventanaConductorActivo = Duration(minutes: 5);

/// Hasta aquí se considera "pocos".
const int umbralPocosConductores = 2;

double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

DisponibilidadConductores calcularDisponibilidad(
  Iterable<ConductorPresente> conductores, {
  required double lat,
  required double lng,
  required DateTime ahora,
}) {
  var carros = 0;
  var motos = 0;
  double? carroCerca;
  double? motoCerca;
  for (final c in conductores) {
    if (ahora.difference(c.visto) > ventanaConductorActivo) continue;
    final metros = distanciaMetros(lat, lng, c.lat, c.lng);
    if (metros > radioBusquedaMetros) continue;
    if (c.esMoto) {
      motos++;
      motoCerca = math.min(motoCerca ?? metros, metros);
    } else {
      carros++;
      carroCerca = math.min(carroCerca ?? metros, metros);
    }
  }
  return DisponibilidadConductores(
    carros: carros,
    motos: motos,
    metrosCarroMasCercano: carroCerca,
    metrosMotoMasCercana: motoCerca,
  );
}

/// Qué decirle al pasajero sobre la espera, si hay algo que decir.
@immutable
class AvisoDisponibilidad {
  const AvisoDisponibilidad(
    this.mensaje, {
    this.ofrecerMoto,
    this.critico = false,
  });

  final String mensaje;

  /// `true`: ofrecer pasar a moto; `false`: a carro; `null`: no hay a qué
  /// cambiar.
  final bool? ofrecerMoto;

  /// No hay ningún conductor del tipo elegido.
  final bool critico;
}

/// `null` si hay conductores de sobra y no hace falta advertir nada.
AvisoDisponibilidad? avisoDisponibilidad(
  DisponibilidadConductores d, {
  required bool esMoto,
}) {
  final propios = esMoto ? d.motos : d.carros;
  final otros = esMoto ? d.carros : d.motos;
  if (propios == 0 && otros > 0) {
    final nombre = esMoto ? 'motos' : 'carros';
    final otro = esMoto
        ? (otros == 1 ? '1 carro' : '$otros carros')
        : (otros == 1 ? '1 moto' : '$otros motos');
    return AvisoDisponibilidad(
      'No hay $nombre cerca ahora, pero sí $otro.',
      ofrecerMoto: !esMoto,
      critico: true,
    );
  }
  if (propios == 0) {
    return const AvisoDisponibilidad(
      'No hay conductores cerca ahora, la espera puede ser mayor.',
      critico: true,
    );
  }
  if (propios <= umbralPocosConductores) {
    return const AvisoDisponibilidad(
      'Pocos conductores disponibles ahora, la espera puede ser mayor.',
    );
  }
  return null;
}

/// Velocidad urbana media para estimar la llegada (Ocaña, calles angostas).
const double _metrosPorMinuto = 25000 / 60;

/// "3–5 min" hasta que llegue el conductor más cercano. Es un estimado grueso
/// (línea recta, sin tráfico): por eso un rango y nunca un minuto exacto.
String? textoTiempoEstimado(double? metros) {
  if (metros == null) return null;
  final minutos = (metros / _metrosPorMinuto).ceil().clamp(1, 60);
  // +1: lo que tarda en aceptar; el rango cubre el trazado real de las calles.
  final desde = minutos + 1;
  return '$desde–${desde + 2} min';
}

/// Lo que se le muestra al pasajero mientras busca. [notificados] es `null`
/// hasta que el servidor termina de repartir.
String textoProgresoBusqueda({required int? notificados, required int vistas}) {
  if (vistas > 0) {
    return vistas == 1
        ? '1 conductor vio tu solicitud'
        : '$vistas conductores vieron tu solicitud';
  }
  if (notificados == null) return 'Notificando a conductores cercanos…';
  if (notificados == 0) {
    return 'Aún no hay conductores cerca. Seguimos buscando.';
  }
  return notificados == 1
      ? 'Avisamos a 1 conductor cercano'
      : 'Avisamos a $notificados conductores cercanos';
}
