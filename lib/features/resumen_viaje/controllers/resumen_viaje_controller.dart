import 'package:flutter/foundation.dart';

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
    if ((resumen.calificacion ?? 0) > 0) {
      _calificacionSeleccionada = (resumen.calificacion ?? 0).clamp(0, 5);
    }
    _comentarioCalificacion = resumen.comentarioCalificacion;
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
