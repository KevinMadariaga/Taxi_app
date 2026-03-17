import 'package:flutter/material.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';

/// Pantalla principal del cliente despues de autenticacion.
/// Reutiliza el flujo consolidado existente de inicio cliente.
class HomeClienteView extends StatelessWidget {
  const HomeClienteView({super.key, this.authUid});

  final String? authUid;

  @override
  Widget build(BuildContext context) {
    return InicioClienteView(authUid: authUid);
  }
}
