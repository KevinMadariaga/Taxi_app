import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/constants/app_constants.dart';
import 'package:taxi_app/screens/usuario_cliente/presentacion/view/InicioClienteView.dart';
import 'package:taxi_app/screens/usuario_conductor/presentacion/view/activacion_servicio_view.dart';

void main() {
  test('publicidad y activación de conductor usan el mismo WhatsApp', () {
    expect(AppConstants.whatsappContacto, '573151770319');
    expect(kWhatsappNumero, AppConstants.whatsappContacto);
  });

  test('el mensaje de publicidad pide lo necesario para cotizar', () {
    for (final parte in [
      'promocionar mi negocio',
      'Planes y precios',
      'Nombre:',
      'Tipo de negocio:',
    ]) {
      expect(mensajePromoWhatsApp, contains(parte));
    }
    // Se manda por URL: tiene que sobrevivir a la codificación.
    final url = Uri.parse(
      'https://wa.me/${AppConstants.whatsappContacto}'
      '?text=${Uri.encodeComponent(mensajePromoWhatsApp)}',
    );
    expect(url.queryParameters['text'], mensajePromoWhatsApp);
  });
}
