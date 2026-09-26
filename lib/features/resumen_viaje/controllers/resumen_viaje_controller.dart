import 'package:flutter/foundation.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';

import '../models/resumen_viaje_model.dart';
import '../services/resumen_viaje_firestore_service.dart';

enum TipoUsuarioResumen { cliente, conductor }

class ResumenViajeController extends ChangeNotifier {
  ResumenViajeController({
    required this.tipoUsuario,
    required this.solicitudId,
    ResumenViajeFirebaseService? firebaseService,
  }) : _firebaseService = firebaseService ?? ResumenViajeFirebaseService();

  final TipoUsuarioResumen tipoUsuario;
  final String solicitudId;
  final ResumenViajeFirebaseService _firebaseService;

  bool _guardando = false;
  double _calificacionSeleccionada = 0;
  String _comentarioCalificacion = '';
  String _conductorId = '';
  bool _sincronizadoDesdeBackend = false;

  /// El conductor ya había calificado a este pasajero (volvió a abrir el
  /// resumen): no se reescribe, las reglas lo rechazarían.
  bool _clienteYaCalificado = false;
  bool _formularioEditado = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Stream<ResumenViajeModel> get resumenStream =>
      _firebaseService.streamResumenViaje(solicitudId);

  bool get guardando => _guardando;
  double get calificacionSeleccionada => _calificacionSeleccionada;
  String get comentarioCalificacion => _comentarioCalificacion;
  bool get esConductor => tipoUsuario == TipoUsuarioResumen.conductor;
  bool get clienteYaCalificado => _clienteYaCalificado;

  bool get requiereComentario =>
      _calificacionSeleccionada > 0 && _calificacionSeleccionada < 3;

  void setCalificacion(double value) {
    final normalized = value.clamp(0, 5).toDouble();
    if (_calificacionSeleccionada == normalized) return;

    _calificacionSeleccionada = normalized;
    _formularioEditado = true;

    if (_calificacionSeleccionada >= 3 && _comentarioCalificacion.isNotEmpty) {
      _comentarioCalificacion = '';
    }

    _safeNotify();
  }

  void setComentario(String value) {
    if (_comentarioCalificacion == value) return;
    _comentarioCalificacion = value;
    _formularioEditado = true;
    _safeNotify();
  }

  void sincronizarFormulario(ResumenViajeModel resumen) {
    if (_disposed) return;
    if (resumen.conductorId.isNotEmpty) _conductorId = resumen.conductorId;
    if (_sincronizadoDesdeBackend || _formularioEditado) return;

    _sincronizadoDesdeBackend = true;
    // Cada rol ve y edita SU calificación: el cliente la del servicio, el
    // conductor la que le da al pasajero.
    final guardada = esConductor
        ? resumen.calificacionCliente
        : resumen.calificacion;
    if ((guardada ?? 0) > 0) {
      _calificacionSeleccionada = guardada!.clamp(0, 5).toDouble();
      _clienteYaCalificado = esConductor;
    }
    _comentarioCalificacion = esConductor
        ? resumen.comentarioCalificacionCliente
        : resumen.comentarioCalificacion;
  }

  String? validarFormularioCliente() {
    if (tipoUsuario != TipoUsuarioResumen.cliente) return null;

    if (_calificacionSeleccionada <= 0) {
      return 'Selecciona una calificacion antes de continuar.';
    }

    if (requiereComentario && _comentarioCalificacion.trim().isEmpty) {
      return 'Debes escribir un comentario para calificaciones menores a 3 estrellas.';
    }

    return null;
  }

  /// Calificación del conductor al pasajero. Es opcional: sin estrellas se
  /// sigue sin escribir nada. Con menos de 3, igual que del lado cliente,
  /// pide un comentario.
  Future<String?> guardarCalificacionConductor() async {
    if (_clienteYaCalificado || _calificacionSeleccionada <= 0) return null;
    if (requiereComentario && _comentarioCalificacion.trim().isEmpty) {
      return 'Cuéntanos qué pasó con el pasajero (menos de 3 estrellas).';
    }

    _guardando = true;
    _safeNotify();
    try {
      await _firebaseService.guardarCalificacionAlCliente(
        solicitudId: solicitudId,
        calificacion: _calificacionSeleccionada,
        comentario: _comentarioCalificacion,
      );
      _clienteYaCalificado = true;
      return null;
    } catch (e, st) {
      // Es opcional: un fallo al escribir (sin red, reglas viejas aún
      // desplegadas) no puede dejar al conductor atrapado en el resumen.
      ErrorReporter.report(e, st, reason: 'resumen: calificar al pasajero');
      return null;
    } finally {
      _guardando = false;
      _safeNotify();
    }
  }

  Future<String?> guardarCalificacionCliente() async {
    final validacion = validarFormularioCliente();
    if (validacion != null) return validacion;

    _guardando = true;
    _safeNotify();

    try {
      await _firebaseService.guardarCalificacion(
        solicitudId: solicitudId,
        calificacion: _calificacionSeleccionada,
        comentarioCalificacion: _comentarioCalificacion,
        conductorId: _conductorId,
      );
      return null;
    } catch (_) {
      return 'No se pudo guardar la calificacion. Intenta nuevamente.';
    } finally {
      _guardando = false;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
