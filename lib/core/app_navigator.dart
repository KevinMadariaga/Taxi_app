import 'package:flutter/material.dart';

/// Clave global del Navigator raíz. Usada por FCM y notificaciones locales
/// para navegar sin BuildContext (background handlers, notification taps).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
