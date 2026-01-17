import 'package:flutter/material.dart';
import 'package:taxi_app/components/boton.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/viewmodel/login_conductor_viewmodel.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/registro_conductor_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/inicio_conductor_view.dart';
import 'package:taxi_app/widgets/sucess_overlay.dart';

class LoginConductorView extends StatefulWidget {
  const LoginConductorView({super.key});

  @override
  State<LoginConductorView> createState() => _LoginConductorViewState();
}

class _LoginConductorViewState extends State<LoginConductorView> {
  late final LoginConductorViewModel vm;

  @override
  void initState() {
    super.initState();
    vm = LoginConductorViewModel();

    // Si ya hay un usuario autenticado, navegar directamente al mapa del conductor
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = vm.currentUser;
      if (user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeConductorMapView()),
        );
      }
    });
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  void _showDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.info, color: Colors.blue),
            const SizedBox(width: 8.0),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "OK",
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final fontScale = width * 0.045;

    return Scaffold(
      appBar: AppBar(
        title: Text("Conductor", style: TextStyle(fontSize: fontScale)),
        backgroundColor: Colores.amarillo,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: width * 0.08),
        child: Form(
          key: vm.formKey,
          child: Column(
            children: [
              SizedBox(height: height * 0.04),
              Image.asset(
                'assets/img/Login.jpg',
                width: width * 0.65,
                height: height * 0.25,
              ),
              SizedBox(height: height * 0.04),
              TextFormField(
                controller: vm.emailController,
                style: TextStyle(fontSize: fontScale),
                decoration: InputDecoration(
                  labelText: "Correo Electrónico",
                  labelStyle: TextStyle(fontSize: fontScale),
                  prefixIcon: const Icon(Icons.email),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Ingrese su correo";
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return "Correo inválido";
                  }
                  return null;
                },
              ),
              SizedBox(height: height * 0.025),
              TextFormField(
                controller: vm.passwordController,
                style: TextStyle(fontSize: fontScale),
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  labelStyle: TextStyle(fontSize: fontScale),
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) => (value == null || value.isEmpty)
                    ? "Ingrese su contraseña"
                    : null,
              ),
              SizedBox(height: height * 0.04),
              ValueListenableBuilder<bool>(
                valueListenable: vm.isLoading,
                builder: (context, loading, _) {
                  return CustomButton(
                    text: loading ? 'Iniciando...' : 'Iniciar Sesión',
                    onPressed: loading
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final ok = await vm.login();
                            if (ok) {
                              if (!mounted) return;
                              await SuccessOverlay.show(
                                context,
                                message: 'Inicio de sesión exitoso',
                              );
                              if (!mounted) return;
                              navigator.pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const HomeConductorMapView(),
                                ),
                              );
                            } else if (vm.error.value != null) {
                              if (!mounted) return;
                              _showDialog('Error', vm.error.value!);
                            }
                          },
                    width: width * 0.45,
                    height: 50,
                    fontSize: width * 0.05,
                  );
                },
              ),
              SizedBox(height: height * 0.02),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegistroConductorView(),
                    ),
                  );
                },
                child: Text(
                  "¿No tienes cuenta? Regístrate",
                  style: TextStyle(
                    fontSize: fontScale * 0.95,
                    color: Colores.amarillo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
