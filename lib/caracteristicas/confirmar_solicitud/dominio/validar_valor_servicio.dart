import 'dart:math' as math;

import 'package:taxi_app/screens/usuario_cliente/presentacion/model/vehicle_type.dart';

import 'casos_uso/calcular_tarifa_base_usecase.dart';
import 'package:taxi_app/core/utils/moneda_format.dart';

/// Reglas de monto del servicio, puras y sin estado.
///
/// Vivían dentro de `ConfirmarSolicitudViewModel`, así que solo las aplicaba
/// el sheet de *antes* de crear la solicitud: los dos caminos de cambiar la
/// oferta con la búsqueda ya en curso exigían únicamente `> 0`, y un `$1`
/// entraba a Firestore igual. Acá afuera las comparten los tres
/// (`TipoVehiculoSheet`, `EditarOfertaBusquedaView` y el diálogo
/// "¿Sigues buscando?", estos dos últimos vía
/// `BuscandoTaxiViewModel.validarNuevoValor`), que es lo que hace que la
/// regla sea una sola y no tres que se desalinean.
///
/// [ahora] es inyectable para poder testear el corte diurno/nocturno sin
/// mockear `DateTime.now()` — mismo criterio que [CalcularTarifaBaseUseCase].

/// Mínimo aceptable: la tarifa base del vehículo (sin el variable por km).
/// Por debajo de eso ningún conductor tomaría el viaje, y ofertas de $1 solo
/// sirven para spamear a todos los conductores del radio.
int valorMinimoPermitido(VehicleType tipo, {DateTime? ahora}) {
  final hora = (ahora ?? DateTime.now()).hour;
  final esNoche = hora >= 18 || hora < 6;
  return esNoche ? tipo.basePriceNoche : tipo.basePriceDia;
}

/// Techo anti fat-finger: 20× el valor sugerido. No busca acotar la
/// negociación, solo evitar que un cero de más quede escrito en Firestore.
///
/// [techoMinimo] sube el piso del techo — sirve cuando todavía no hay ruta
/// trazada y el sugerido saldría sin el componente por km, que dejaría por
/// debajo a un valor que ya está vigente en la solicitud.
int valorMaximoPermitido(
  VehicleType tipo, {
  double? distanciaKm,
  DateTime? ahora,
  int techoMinimo = 0,
}) {
  final sugerido =
      int.tryParse(
        const CalcularTarifaBaseUseCase()(
          tipo,
          ahora: ahora,
          distanciaKm: distanciaKm,
        ),
      ) ??
      10000;
  return math.max(sugerido * 20, techoMinimo);
}

/// `null` si [digits] es un valor aceptable; si no, el motivo para mostrar en
/// la UI. Acepta el texto crudo del input (puede traer separadores de miles).
String? validarValorServicio(
  String digits, {
  required VehicleType tipo,
  double? distanciaKm,
  DateTime? ahora,
  int techoMinimo = 0,
}) {
  final minimo = valorMinimoPermitido(tipo, ahora: ahora);
  final maximo = valorMaximoPermitido(
    tipo,
    distanciaKm: distanciaKm,
    ahora: ahora,
    techoMinimo: techoMinimo,
  );
  final valor = int.tryParse(digits.replaceAll(RegExp(r'[^0-9]'), ''));
  if (valor == null || valor <= 0) return 'Ingresa un valor válido.';
  if (valor < minimo) {
    return 'El valor mínimo para ${tipo.label.toLowerCase()} es '
        '\$${formatCurrency(minimo)}.';
  }
  if (valor > maximo) {
    return 'El valor máximo es \$${formatCurrency(maximo)}.';
  }
  return null;
}
