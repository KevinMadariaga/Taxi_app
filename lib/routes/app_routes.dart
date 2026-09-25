import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/presentation/screens/splash/splash_view.dart';
import 'package:taxi_app/presentation/viewmodels/splash/splash_viewmodel.dart';
import 'package:taxi_app/caracteristicas/autenticacion/presentacion/vistas/home_screen.dart';
import 'package:taxi_app/core/constants/rutas_app.dart';
import 'package:taxi_app/core/utils/transicion_pagina.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/home_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscando_taxi_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ResumenClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/resumen_conductor_view.dart';
import 'package:taxi_app/features/admin/admin_home_screen.dart';
import 'package:taxi_app/features/phone_auth/screens/admin_hub_screen.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/InicioConductorView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/estado_solicitud_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/cambiar_destino_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/problemas_conductor_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda/metodo_pago_view.dart';

/// Construye las rutas; los nombres viven en [RutasApp].
class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments is Map
        ? (settings.arguments as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    switch (settings.name) {
      case RutasApp.splash:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => SplashViewModel(),
            child: const SplashView(),
          ),
        );
      case RutasApp.login:
        return MaterialPageRoute(builder: (_) => const HomeView());
      case RutasApp.adminHome:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              AdminHomeScreen(adminId: (args['adminId'] ?? '').toString()),
        );
      case RutasApp.adminHub:
        final tab = args['initialTab'];
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AdminHubScreen(initialTab: tab is int ? tab : 0),
        );
      case RutasApp.conductorInicio:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => InicioConductor(
            mostrarBienvenida: args['mostrarBienvenida'] == true,
          ),
        );
      case RutasApp.clienteInicio:
        final authUid = args['authUid'] as String?;
        if (args['transicionInicio'] == true) {
          return transicionInicioCliente(HomeClienteView(authUid: authUid));
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => HomeClienteView(authUid: authUid),
        );
      case RutasApp.buscandoTaxi:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => BuscandoTaxiView(
            solicitudId: args['solicitudId'] as String?,
            initialClientLocation: args['initialClientLocation'] as LatLng?,
          ),
        );
      case RutasApp.resumenCliente:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ResumenClienteView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
          ),
        );
      case RutasApp.resumenConductor:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ResumenConductorView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
          ),
        );
      case RutasApp.ayudaEstadoSolicitud:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => EstadoSolicitudView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
          ),
        );
      case RutasApp.ayudaCambiarDestino:
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
      case RutasApp.ayudaProblemasConductor:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProblemasConductorView(
            solicitudId: (args['solicitudId'] ?? '').toString(),
            nombreConductor: (args['nombreConductor'] ?? '').toString(),
          ),
        );
      case RutasApp.ayudaMetodoPago:
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
