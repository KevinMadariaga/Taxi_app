import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/core/utils/app_dependencies.dart';
import 'package:taxi_app/presentation/screens/splash/splash_view.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/viewmodels/login_viewmodel.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/estado_solicitud_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/cambiar_destino_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/problemas_conductor_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/metodo_pago_view.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';

  // Pantallas de la sección "Ayuda" del cliente.
  static const String ayudaEstadoSolicitud = '/ayuda/estado-solicitud';
  static const String ayudaCambiarDestino = '/ayuda/cambiar-destino';
  static const String ayudaProblemasConductor = '/ayuda/problemas-conductor';
  static const String ayudaMetodoPago = '/ayuda/metodo-pago';

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings,
    AppDependencies dependencies,
  ) {
    final args = settings.arguments is Map
        ? (settings.arguments as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => SplashViewModel(),
            child: const SplashView(),
          ),
        );
      case login:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => LoginViewModel(
              sendPhoneOtpUseCase: dependencies.sendPhoneOtpUseCase,
            ),
            child: const HomeView(),
          ),
        );
      case ayudaEstadoSolicitud:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => EstadoSolicitudView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
          ),
        );
      case ayudaCambiarDestino:
        final lat = args['lat'];
        final lng = args['lng'];
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CambiarDestinoView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
            destinoInicial: (lat is num && lng is num)
                ? LatLng(lat.toDouble(), lng.toDouble())
                : null,
            direccionInicial: (args['direccion'] ?? '').toString(),
          ),
        );
      case ayudaProblemasConductor:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProblemasConductorView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
            nombreConductor: (args['nombreConductor'] ?? '').toString(),
          ),
        );
      case ayudaMetodoPago:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => MetodoPagoView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
            metodoActual: (args['metodoActual'] ?? '').toString(),
          ),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Ruta no encontrada')),
            body: Center(child: Text('No existe la ruta: ${settings.name}')),
          ),
        );
    }
  }
}
