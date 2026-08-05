import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre Google Maps externo con ruta hacia [destino] — único punto de esta
/// lógica, que hasta ahora estaba duplicada e independiente en
/// `driver_trip_screen.dart` y `RutaDestinoView.dart` (conductor), cada una
/// armando su propia URL a mano.
class NavegacionExternaDatasource {
  Future<void> abrirRutaHacia(LatLng destino) async {
    final googleNav = Uri.parse(
      'google.navigation:q=${destino.latitude},${destino.longitude}&mode=d',
    );
    if (await canLaunchUrl(googleNav)) {
      await launchUrl(googleNav, mode: LaunchMode.externalApplication);
      return;
    }

    final webFallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${destino.latitude},${destino.longitude}&travelmode=driving',
    );
    await launchUrl(webFallback, mode: LaunchMode.externalApplication);
  }
}
