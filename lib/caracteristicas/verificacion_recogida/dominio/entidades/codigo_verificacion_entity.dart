/// Código de verificación de recogida: el cliente lo ve en pantalla y se lo
/// dice de viva voz al conductor cuando llega; el conductor lo ingresa para
/// validar la solicitud y habilitar el tramo hacia el destino.
class CodigoVerificacionEntity {
  const CodigoVerificacionEntity({
    required this.codigo,
    required this.generadoEn,
    required this.validadoEn,
    this.intentosFallidos = 0,
  });

  /// 4 dígitos numéricos, ej. "4821". Vacío si todavía no se generó.
  final String codigo;
  final DateTime? generadoEn;
  final DateTime? validadoEn;
  final int intentosFallidos;

  bool get generado => codigo.isNotEmpty;
  bool get validado => validadoEn != null;

  static const CodigoVerificacionEntity vacio = CodigoVerificacionEntity(
    codigo: '',
    generadoEn: null,
    validadoEn: null,
    intentosFallidos: 0,
  );

  CodigoVerificacionEntity copyWith({
    String? codigo,
    DateTime? generadoEn,
    DateTime? validadoEn,
    int? intentosFallidos,
  }) {
    return CodigoVerificacionEntity(
      codigo: codigo ?? this.codigo,
      generadoEn: generadoEn ?? this.generadoEn,
      validadoEn: validadoEn ?? this.validadoEn,
      intentosFallidos: intentosFallidos ?? this.intentosFallidos,
    );
  }
}
