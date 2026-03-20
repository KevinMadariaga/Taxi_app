class SolicitudEstado {
  SolicitudEstado._();

  static const String buscando = 'buscando';
  static const String asignado = 'asignado';
  static const String enEspera = 'en espera';
  static const String enCamino = 'en camino';
  static const String enRuta = 'en ruta';
  static const String completado = 'completado';
  static const String cancelado = 'cancelado';
  static const String sinRespuesta = 'sin respuesta';

  static String normalize(String value) {
    final raw = value.toLowerCase().trim();
    if (raw.isEmpty) return raw;

    final compact = raw.replaceAll('_', ' ').replaceAll('-', ' ');

    if (compact.contains('en ruta') || compact.contains('enruta')) {
      return enRuta;
    }
    if (compact.contains('en camino') || compact.contains('encam')) {
      return enCamino;
    }
    if (compact.contains('en espera') || compact.contains('enespera')) {
      return enEspera;
    }
    if (compact.contains('asignado') || compact.contains('assigned')) {
      return asignado;
    }
    if (compact.contains('buscand')) {
      return buscando;
    }
    if (compact.contains('cancel')) {
      return cancelado;
    }
    if (compact.contains('sin respuesta') ||
        compact.contains('sinrespuesta') ||
        compact.contains('no responde') ||
        compact.contains('no response')) {
      return sinRespuesta;
    }
    if (compact.contains('complet') ||
        compact.contains('completed') ||
        compact.contains('finaliz')) {
      return completado;
    }

    return compact;
  }

  static bool isSesionActiva(String normalized) {
    return normalized == asignado ||
        normalized == enEspera ||
        normalized == enCamino ||
        normalized == enRuta;
  }

  static bool isTerminal(String normalized) {
    return normalized == cancelado ||
        normalized == completado ||
        normalized == sinRespuesta;
  }
}
