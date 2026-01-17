import 'package:flutter/material.dart';
import 'package:taxi_app/core/app_colores.dart';
import 'package:taxi_app/helper/responsive_helper.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/login_cliente_view.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/login_conductor_view.dart';




class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Ajuste dinámico según el tamaño de la pantalla
    final isSmallScreen = screenHeight < 600;
    final imgHeight = isSmallScreen 
        ? ResponsiveHelper.hp(context, 25) 
        : ResponsiveHelper.hp(context, 45);
    final spacerSmall = ResponsiveHelper.hp(context, 1);
    final spacerLarge = isSmallScreen 
        ? ResponsiveHelper.hp(context, 4) 
        : ResponsiveHelper.hp(context, 6);
    final buttonHorizontal = ResponsiveHelper.wp(context, 20);
    final buttonVertical = ResponsiveHelper.hp(context, 1.8);
    final titleFont = ResponsiveHelper.sp(context, 17);
    final buttonFont = ResponsiveHelper.sp(context, 19);
    final iconSize = ResponsiveHelper.hp(context, 6);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.wp(context, 5),
                      vertical: ResponsiveHelper.hp(context, 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 1),
                        
                         // Imagen del taxi
                        Image.asset(
                          'assets/img/home.png', 
                          height: imgHeight,
                          fit: BoxFit.contain,
                        ),
                        
                        SizedBox(height: spacerSmall),
                        
                        // Título
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.wp(context, 2),
                          ),
                          child: Text(
                            'Viaja seguro, rápido y con confianza',
                            style: TextStyle(
                              fontSize: titleFont,
                              fontWeight: FontWeight.w500,
                              color: AppColores.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        SizedBox(height: spacerLarge),

                        // Botón Clientes
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonHorizontal,
                              vertical: buttonVertical,
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const Login(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textPrimary,
                                padding: EdgeInsets.symmetric(
                                  vertical: buttonVertical,
                                  horizontal: ResponsiveHelper.wp(context, 4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                                elevation: 3,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: iconSize,
                                    color: AppColores.textPrimary,
                                  ),
                                  SizedBox(width: ResponsiveHelper.wp(context, 3)),
                                  Flexible(
                                    child: Text(
                                      "Cliente",
                                      style: TextStyle(
                                        fontSize: buttonFont,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Botón Conductor
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonHorizontal,
                              vertical: buttonVertical,
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginConductorView(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColores.buttonPrimary,
                                foregroundColor: AppColores.textPrimary,
                                padding: EdgeInsets.symmetric(
                                  vertical: buttonVertical,
                                  horizontal: ResponsiveHelper.wp(context, 4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                                elevation: 3,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.drive_eta,
                                    size: iconSize,
                                    color: AppColores.textPrimary,
                                  ),
                                  SizedBox(width: ResponsiveHelper.wp(context, 3)),
                                  Flexible(
                                    child: Text(
                                      "Conductor",
                                      style: TextStyle(
                                        fontSize: buttonFont,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const Spacer(flex: 1),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
