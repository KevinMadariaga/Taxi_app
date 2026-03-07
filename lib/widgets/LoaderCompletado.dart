import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:taxi_app/core/app_colores.dart';

class LoaderSolicitudCompletada extends StatelessWidget {
  final String texto;
  const LoaderSolicitudCompletada({
    Key? key,
    this.texto = 'Terminando viaje...',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpinKitCircle(
              color: AppColores.primary,
              size: 60.0,
            ),
            const SizedBox(height: 24),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
