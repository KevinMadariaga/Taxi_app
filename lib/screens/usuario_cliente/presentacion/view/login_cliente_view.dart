import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/inicio_cliente_view.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/viewmodels/autenticacion_viewmodel.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/registro_cliente_view.dart';


class Login extends StatelessWidget {
  const Login({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Iniciar Sesión",
          style: TextStyle(fontSize: 20.0),
        ),
        backgroundColor: AppColores.primary,
        elevation: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              children: [
                SizedBox(height: 40.0),
                // Use an icon instead of image for safety
                            Image.asset(
                'assets/img/Login.jpg',
                width: 250,
                height: 250,
              ),
              
                SizedBox(height: 20.0),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Correo Electrónico",
                    labelStyle: TextStyle(fontSize: 14.0),
                    prefixIcon: Icon(
                      Icons.email,
                      size: 22,
                    ),
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 20.0,
                    ),
                  ),
                  style: TextStyle(fontSize: 16.0),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (value) => vm.setEmail(value),
                ),
                SizedBox(height: 20.0),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "Contraseña",
                    labelStyle: TextStyle(fontSize: 14.0),
                    prefixIcon: Icon(
                      Icons.lock,
                      size: 22,
                    ),
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 20.0,
                    ),
                  ),
                  style: TextStyle(fontSize: 16.0),
                  obscureText: true,
                  onChanged: (value) => vm.setPassword(value),
                ),
                SizedBox(height: 20.0),
                vm.isLoading
                    ? SizedBox(
                        width: 100,
                        height: 100,
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : CustomButton(
                        text: 'Iniciar Sesión',
                        onPressed: () async {
                          await vm.login();

                          if (vm.isAuthenticated) {
                            // Mostrar animación de confirmación si existe el JSON, si no mostrar icono
                            final hasJson = await (() async {
                              try {
                                await rootBundle.loadString('assets/gif/confirmacion_animada.json');
                                return true;
                              } catch (_) {
                                return false;
                              }
                            })();

                            // Mostrar diálogo (no esperamos al pop)
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: SizedBox(
                                    width: 220,
                                    height: 220,
                                    child: hasJson
                                        ? Lottie.asset('assets/gif/confirmacion_animada.json', fit: BoxFit.contain)
                                        : const Center(
                                            child: Icon(Icons.check_circle, color: Colors.green, size: 96),
                                          ),
                                  ),
                                ),
                              );

                              // Esperar y cerrar diálogo
                              await Future.delayed(const Duration(seconds: 2));
                              if (Navigator.canPop(context)) Navigator.of(context).pop();

                              // Navegar a InicioClienteView
                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const InicioClienteView()),
                                );
                              }

                              vm.clearAuthenticated();
                            }
                          }
                        },
                        width: 100,
                        height: 50,
                        fontSize: 16.0,
                      ),
                if (vm.errorMessage != null) ...[
                  SizedBox(height: 12.0),
                  Text(
                    vm.errorMessage!,
                    style: TextStyle(color: Colors.red, fontSize: 14.0),
                    textAlign: TextAlign.center,
                  ),
                ],
                SizedBox(height: 20.0),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegistroClienteView()),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 20.0,
                    ),
                  ),
                  child: Text(
                    "¿No tienes cuenta? Regístrate",
                    style: TextStyle(
                      color: AppColores.primary,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 20.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
