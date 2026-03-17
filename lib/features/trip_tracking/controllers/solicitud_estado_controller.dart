import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/services/notification_service.dart';

import '../services/firebase_service.dart';
import '../widgets/waiting_driver_modal.dart';

class SolicitudEstadoController {
  SolicitudEstadoController({
    FirebaseService? firebaseService,
    NotificationService? notificationService,
  }) : _firebaseService = firebaseService ?? FirebaseService(),
       _notificationService =
           notificationService ?? NotificationService.instance;

  final FirebaseService _firebaseService;
  final NotificationService _notificationService;

  final ValueNotifier<int> _remainingSeconds = ValueNotifier<int>(180);

  Timer? _countdownTimer;
  String? _lastEstado;
  bool _isWaitModalVisible = false;
  bool _isUpdatingEstado = false;
  bool _rutaNotified = false;
  bool _notificationInitialized = false;
  bool _disposed = false;
  BuildContext? _sheetContext;

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

    if (estado != 'en_espera') {
      await _closeWaitModalIfNeeded();
    }

    if (estado == 'en_espera') {
      _rutaNotified = false;
      await _openWaitModal(context: context, solicitudId: solicitudId);
      return;
    }

    if (estado == 'en_ruta') {
      if (_rutaNotified) return;
      _rutaNotified = true;

      await _notify(
        title: 'Viaje en curso',
        body: 'Conductor encontrado, ya vendrá a recogerte.',
      );
      await onIrRutaClienteDestino();
      return;
    }

    if (estado == 'en_camino') {
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
    _startCountdown();

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
                    estado: 'en camino',
                  );
                  await _closeWaitModalIfNeeded();
                } finally {
                  _isUpdatingEstado = false;
                  if (!context.mounted) return;
                  setModalState(() {});
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
    });
  }

  void _startCountdown() {
    _stopCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds.value <= 0) {
        _stopCountdown();
        return;
      }
      _remainingSeconds.value = _remainingSeconds.value - 1;
    });
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
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
      );
    } catch (_) {}
  }

  static String normalizeEstado(String value) {
    final raw = value.toLowerCase().trim();
    final compact = raw.replaceAll('_', ' ').replaceAll('-', ' ');

    if (compact.contains('en ruta') || compact.contains('enruta')) {
      return 'en_ruta';
    }
    if (compact.contains('en camino') || compact.contains('encam')) {
      return 'en_camino';
    }
    if (compact.contains('en espera') || compact.contains('enespera')) {
      return 'en_espera';
    }
    if (compact.contains('cancel')) {
      return 'cancelado';
    }
    return compact;
  }

  void dispose() {
    _disposed = true;
    _stopCountdown();
    _remainingSeconds.dispose();
  }
}
