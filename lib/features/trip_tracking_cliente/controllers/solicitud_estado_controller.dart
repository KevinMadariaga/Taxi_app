import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/constants/solicitud_estado.dart';
import 'package:taxi_app/core/services/services.dart';

import '../services/trip_tracking_firestore_service.dart';
import '../widgets/waiting_driver_modal.dart';

class SolicitudEstadoController {
  SolicitudEstadoController({
    TripTrackingFirebaseService? firebaseService,
    NotificacionesServicio? notificationService,
  }) : _firebaseService = firebaseService ?? TripTrackingFirebaseService(),
       _notificationService =
           notificationService ?? NotificacionesServicio.instance;

  final TripTrackingFirebaseService _firebaseService;
  final NotificacionesServicio _notificationService;

  final ValueNotifier<int> _remainingSeconds = ValueNotifier<int>(180);
  // Notifier to indicate whether the waiting modal is currently visible.
  final ValueNotifier<bool> waitModalVisible = ValueNotifier<bool>(false);

  Timer? _countdownTimer;
  String? _lastEstado;
  bool _isWaitModalVisible = false;
  bool _isUpdatingEstado = false;
  bool _rutaNotified = false;
  bool _notificationInitialized = false;
  bool _disposed = false;
  BuildContext? _sheetContext;
  bool _timeoutHandled = false;

  ValueNotifier<int> get remainingSeconds => _remainingSeconds;
  bool get isUpdatingEstado => _isUpdatingEstado;

  Future<void> handleEstadoCambio({
    required BuildContext context,
    required String solicitudId,
    required String estadoRaw,
    required Future<void> Function() onIrRutaClienteDestino,
  }) async {
    final estado = normalizeEstado(estadoRaw);
    if (estado == _lastEstado) return;

    _lastEstado = estado;

    if (estado != SolicitudEstado.enEspera) {
      await _closeWaitModalIfNeeded();
    }

    if (estado == SolicitudEstado.enEspera) {
      _rutaNotified = false;
      // Notificación local (funciona en primer y segundo plano).
      unawaited(
        _notify(
          title: 'Tu conductor llegó',
          body: 'El conductor está afuera esperándote.',
        ),
      );
      if (!context.mounted) return;
      await _openWaitModal(context: context, solicitudId: solicitudId);
      return;
    }

    if (estado == SolicitudEstado.enRuta) {
      if (_rutaNotified) return;
      _rutaNotified = true;

      unawaited(
        _notify(
          title: 'Viaje iniciado',
          body: 'Comenzó el viaje hacia el destino.',
        ),
      );

      await onIrRutaClienteDestino();
      return;
    }

    if (estado == SolicitudEstado.enCamino) {
      _rutaNotified = false;
    }
  }

  Future<void> _openWaitModal({
    required BuildContext context,
    required String solicitudId,
  }) async {
    if (_isWaitModalVisible || _disposed || !context.mounted) return;

    _isWaitModalVisible = true;
    _remainingSeconds.value = 180;
    _timeoutHandled = false;
    _startCountdown(solicitudId: solicitudId);

    try {
      waitModalVisible.value = true;
    } catch (_) {}

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return WaitingDriverModal(
              remainingSeconds: remainingSeconds,
              isUpdating: isUpdatingEstado,
              onVoyEnCamino: () async {
                if (_isUpdatingEstado) return;
                _isUpdatingEstado = true;
                setModalState(() {});

                try {
                  await _firebaseService.actualizarEstadoSolicitud(
                    solicitudId: solicitudId,
                    estado: SolicitudEstado.enCamino,
                  );
                  await _closeWaitModalIfNeeded();
                } finally {
                  _isUpdatingEstado = false;
                  if (context.mounted) {
                    setModalState(() {});
                  }
                }
              },
            );
          },
        );
      },
    ).whenComplete(() {
      _isWaitModalVisible = false;
      _sheetContext = null;
      _stopCountdown();
      _isUpdatingEstado = false;
      try {
        waitModalVisible.value = false;
      } catch (_) {}
    });
  }

  void _startCountdown({required String solicitudId}) {
    _stopCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds.value <= 0) {
        _stopCountdown();
        if (_timeoutHandled || _isUpdatingEstado) return;
        _timeoutHandled = true;
        unawaited(_markNoResponseTimeout(solicitudId));
        return;
      }
      _remainingSeconds.value = _remainingSeconds.value - 1;
    });
  }

  Future<void> _markNoResponseTimeout(String solicitudId) async {
    try {
      _isUpdatingEstado = true;
      await _firebaseService.actualizarEstadoSolicitud(
        solicitudId: solicitudId,
        estado: SolicitudEstado.sinRespuesta,
      );
      await _closeWaitModalIfNeeded();
      await _notify(
        title: 'Solicitud cancelada',
        body: 'No confirmaste a tiempo. La solicitud quedó sin respuesta.',
      );
    } catch (_) {
      _timeoutHandled = false;
    } finally {
      _isUpdatingEstado = false;
    }
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _closeWaitModalIfNeeded() async {
    if (!_isWaitModalVisible) {
      _stopCountdown();
      return;
    }

    _stopCountdown();
    final ctx = _sheetContext;
    if (ctx == null) return;

    try {
      Navigator.of(ctx).pop();
    } catch (_) {}
  }

  Future<void> _notify({required String title, required String body}) async {
    try {
      if (!_notificationInitialized) {
        await _notificationService.init();
        _notificationInitialized = true;
      }

      await _notificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
      );
    } catch (_) {}
  }

  static String normalizeEstado(String value) {
    return SolicitudEstado.normalize(value);
  }

  void dispose() {
    _disposed = true;
    _stopCountdown();
    _remainingSeconds.dispose();
    try {
      waitModalVisible.dispose();
    } catch (_) {}
  }
}
