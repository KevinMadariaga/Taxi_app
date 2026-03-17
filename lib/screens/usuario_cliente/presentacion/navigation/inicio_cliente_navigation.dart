import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/model/location_model.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/buscar_destino_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/DetailsSolicitud.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/MapaPreviewView.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/ayuda_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/configuracion_aplicacion_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/historial_viaje_cliente.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/notificaciones_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/seguridad_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/soporte_view.dart';
import 'package:taxi_app/widgets/perfil.dart';

class InicioClienteNavigation {
  static Future<void> irAPerfil(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PaginaPerfilUsuario(tipoUsuario: 'cliente'),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  static Future<void> irAHistorial(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HistorialCliente()));
  }

  static Future<void> irAConfiguracion(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracionAplicacionView()),
    );
  }

  static Future<void> irASeguridad(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SeguridadView()));
  }

  static Future<void> irAAyuda(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AyudaView()));
  }

  static Future<void> irASoporte(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SoporteView()));
  }

  static Future<void> irANotificaciones(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificacionesView()));
  }

  static Future<void> irADestinoSeleccion(
    BuildContext context,
    LatLng? currentLocation,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BuscarDestinoView(currentLocation: currentLocation),
      ),
    );
  }

  static Future<void> irAMapaPreview(
    BuildContext context,
    LocationModel origen,
    LocationModel destino,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapPreview(origen: origen, destino: destino),
      ),
    );
  }

  static Future<void> irAMapaPreviewFavoritoCasa(
    BuildContext context,
    LatLng location,
    String direccion,
  ) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MapaPreviewView(location: location, direccion: direccion),
      ),
    );
  }
}
