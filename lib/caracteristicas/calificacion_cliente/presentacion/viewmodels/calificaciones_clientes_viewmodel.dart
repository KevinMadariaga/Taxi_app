import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../../dominio/entidades/calificacion_cliente.dart';
import '../../dominio/repositorios/calificacion_cliente_repository.dart';

/// Caché por sesión de los promedios de clientes. La comparten la tarjeta de
/// solicitud entrante, la del viaje y el perfil: cada cliente se lee una sola
/// vez aunque su tarjeta se reconstruya muchas veces.
class CalificacionesClientesViewModel extends ChangeNotifier {
  CalificacionesClientesViewModel(this._repository);

  final CalificacionClienteRepository _repository;
  final Map<String, CalificacionCliente?> _cache = {};
  final Set<String> _cargando = {};
  bool _disposed = false;

  /// Promedio de [clienteId] si ya se cargó; si no, pide la carga y devuelve
  /// `null` hasta que llegue (entonces notifica).
  CalificacionCliente? de(String clienteId) {
    if (clienteId.isEmpty) return null;
    if (!_cache.containsKey(clienteId) && _cargando.add(clienteId)) {
      // Fuera del build que la pidió: notificar durante un build lanza.
      scheduleMicrotask(() => _cargar(clienteId));
    }
    return _cache[clienteId];
  }

  bool cargado(String clienteId) => _cache.containsKey(clienteId);

  Future<void> _cargar(String clienteId) async {
    try {
      _cache[clienteId] = await _repository.obtener(clienteId);
    } catch (e, st) {
      // Se guarda el null igual: reintentar en cada build haría una lectura
      // de Firestore por frame si el error persiste (sin red, permisos).
      _cache[clienteId] = null;
      ErrorReporter.report(e, st, reason: 'calificacion_cliente: obtener');
    } finally {
      _cargando.remove(clienteId);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
