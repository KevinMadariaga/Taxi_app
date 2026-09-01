import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taxi_app/core/services/app_remote_config_service.dart';
import 'package:taxi_app/core/services/conectividad_service.dart';
import 'package:taxi_app/core/utils/error_reporter.dart';
import 'package:taxi_app/core/widgets/sin_conexion_dialog.dart';

/// Envuelve la app entera (mismo rol que `AppUpdateGate`) y avisa con un
/// modal apenas detecta que no hay conexión — al arrancar (sobre el splash)
/// y ante cualquier caída posterior, en cualquier pantalla, cliente o
/// conductor. Antes de esto no existía ningún chequeo proactivo: la app se
/// quedaba mostrando pantallas rotas en silencio (el mapa estático del home
/// de cliente/conductor era el caso reportado) sin decirle al usuario que el
/// problema era la conexión.
///
/// El aviso se muestra como `OverlayEntry`, no como ruta de `Navigator`
/// (`showDialog`/`showGeneralDialog`) — una ruta normal puede ser
/// reemplazada por cualquier `Navigator.pushReplacement` que corra en
/// paralelo mientras está arriba (p. ej. el splash resolviendo la pantalla
/// inicial), revelando de golpe lo que estuviera debajo. El `OverlayEntry`
/// vive por fuera de ese stack: solo este gate lo inserta/retira, y solo
/// ante la conectividad real — nada de navegación puede tocarlo.
class ConectividadGate extends StatefulWidget {
  const ConectividadGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<ConectividadGate> createState() => _ConectividadGateState();
}

class _ConectividadGateState extends State<ConectividadGate> {
  StreamSubscription<bool>? _sub;
  // Evita reabrir el aviso en cada emisión mientras sigue offline (el stream
  // de connectivity_plus puede emitir varias veces sin que el estado
  // realmente cambie) — solo reacciona a una transición nueva.
  bool? _ultimoEstadoConectado;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    unawaited(_chequeoInicial());
    _sub = ConectividadService.instance.onConectividadCambia.listen(
      _onCambioConectividad,
      onError: (e, st) =>
          ErrorReporter.report(e, st, reason: 'conectividad_gate'),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _quitarOverlay();
    super.dispose();
  }

  Future<void> _chequeoInicial() async {
    try {
      final conectado = await ConectividadService.instance.hayConexion();
      _onCambioConectividad(conectado);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'conectividad_gate');
    }
  }

  void _onCambioConectividad(bool conectado) {
    final eraOffline = _ultimoEstadoConectado == false;
    _ultimoEstadoConectado = conectado;

    if (!conectado) {
      _mostrarOverlaySiHaceFalta();
      return;
    }

    // Volvió la conexión: el mapa estático puede recuperarse solo, sin
    // exigirle al usuario reiniciar la app.
    if (eraOffline) {
      AppRemoteConfigService.instance.invalidateStaticMapsKeyCache();
    }
    _quitarOverlay();
  }

  void _mostrarOverlaySiHaceFalta() {
    if (_overlayEntry != null) return;
    final overlayState = widget.navigatorKey.currentState?.overlay;
    if (overlayState == null) {
      // El Overlay del Navigator todavía no existe (primer frame en curso) —
      // reintenta después del build sin perder la transición a offline.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ultimoEstadoConectado == false) {
          _mostrarOverlaySiHaceFalta();
        }
      });
      return;
    }

    _overlayEntry = OverlayEntry(builder: (_) => const SinConexionOverlay());
    overlayState.insert(_overlayEntry!);
  }

  void _quitarOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
